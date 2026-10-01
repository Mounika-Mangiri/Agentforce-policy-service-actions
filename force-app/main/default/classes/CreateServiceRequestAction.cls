/**
 * Agent action: opens a Case for a service request on a verified customer's
 * policy, so a human team completes it. The agent never changes the policy.
 */
public with sharing class CreateServiceRequestAction {
  public static final Set<String> REQUEST_TYPES = new Set<String>{
    'Address Change',
    'Beneficiary Change',
    'Payment Question',
    'Other'
  };
  private static final Integer MAX_DETAILS = 2000;

  public class Request {
    @InvocableVariable(
      label='Policy Number'
      description='Policy number the request is about.'
      required=true
    )
    public String policyNumber;

    @InvocableVariable(
      label='Verified Contact Id'
      description='Id of the Contact verified earlier in this conversation.'
      required=true
    )
    public Id verifiedContactId;

    @InvocableVariable(
      label='Request Type'
      description='One of: Address Change, Beneficiary Change, Payment Question, Other.'
      required=true
    )
    public String requestType;

    @InvocableVariable(
      label='Details'
      description='What the customer wants, in their words. Do not include card or bank numbers.'
      required=true
    )
    public String details;
  }

  public class Response {
    @InvocableVariable(
      label='Success'
      description='True when the case was created.'
    )
    public Boolean success = false;

    @InvocableVariable(
      label='Case Number'
      description='Case number to give the customer.'
    )
    public String caseNumber;

    @InvocableVariable(
      label='Message'
      description='Plain-language result to relay to the customer.'
    )
    public String message;
  }

  @InvocableMethod(
    label='Create Policy Service Request'
    description='Creates a service case for a change or question on the verified customer\'s policy. Use after confirming the request type and details with the customer.'
    category='Policy Service'
  )
  public static List<Response> create(List<Request> requests) {
    List<String> numbers = new List<String>();
    for (Request r : requests) {
      numbers.add(r.policyNumber);
    }
    Map<String, Policy__c> policies = PolicyLookup.byNumber(
      PolicyLookup.normalize(numbers)
    );

    List<Response> responses = new List<Response>();
    List<Case> cases = new List<Case>();
    List<Integer> caseIndex = new List<Integer>();

    for (Integer i = 0; i < requests.size(); i++) {
      Request r = requests[i];
      Response res = new Response();
      responses.add(res);
      String problem = validate(r);
      Policy__c p = PolicyLookup.ownedBy(
        policies,
        r.policyNumber,
        r.verifiedContactId
      );
      if (problem == null && p == null) {
        problem = GetPolicySummaryAction.NOT_FOUND;
      }
      if (problem != null) {
        res.message = problem;
        continue;
      }
      cases.add(
        new Case(
          ContactId = r.verifiedContactId,
          Subject = r.requestType + ' - ' + p.Name,
          Description = r.details.trim(),
          Origin = 'Web'
        )
      );
      caseIndex.add(i);
    }

    insertCases(cases, caseIndex, responses);
    return responses;
  }

  private static String validate(Request r) {
    if (
      String.isBlank(r.requestType) || !REQUEST_TYPES.contains(r.requestType)
    ) {
      return 'Request type must be one of: ' +
        String.join(new List<String>(REQUEST_TYPES), ', ') +
        '.';
    }
    if (String.isBlank(r.details)) {
      return 'Please describe what the customer needs.';
    }
    if (r.details.length() > MAX_DETAILS) {
      return 'Details are too long; keep them under 2,000 characters.';
    }
    return null;
  }

  private static void insertCases(
    List<Case> cases,
    List<Integer> caseIndex,
    List<Response> responses
  ) {
    if (cases.isEmpty()) {
      return;
    }
    List<Database.SaveResult> results = Database.insert(
      cases,
      false,
      AccessLevel.USER_MODE
    );
    Set<Id> created = new Set<Id>();
    for (Database.SaveResult sr : results) {
      if (sr.isSuccess()) {
        created.add(sr.getId());
      }
    }
    Map<Id, Case> numbers = new Map<Id, Case>(
      [SELECT Id, CaseNumber FROM Case WHERE Id IN :created WITH USER_MODE]
    );
    for (Integer j = 0; j < results.size(); j++) {
      Response res = responses[caseIndex[j]];
      if (results[j].isSuccess()) {
        res.success = true;
        res.caseNumber = numbers.get(results[j].getId()).CaseNumber;
        res.message =
          'Created case ' +
          res.caseNumber +
          '. The service team will follow up.';
      } else {
        res.message = 'The request could not be created. A person will need to help.';
      }
    }
  }
}
