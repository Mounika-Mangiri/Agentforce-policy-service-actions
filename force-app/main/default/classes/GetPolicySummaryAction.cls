/**
 * Agent action: read-only policy summary for a verified customer.
 * Labels and descriptions below are what the Agentforce planner reads when
 * deciding whether and how to call the action, so they are written as
 * instructions.
 */
public with sharing class GetPolicySummaryAction {
  public static final String NOT_FOUND = 'I could not find that policy for the verified customer. Ask them to check the policy number.';

  public class Request {
    @InvocableVariable(
      label='Policy Number'
      description='Policy number exactly as the customer gave it, for example DEMO-TL-100001.'
      required=true
    )
    public String policyNumber;

    @InvocableVariable(
      label='Verified Contact Id'
      description='Id of the Contact whose identity was already verified in this conversation. Never guess this value.'
      required=true
    )
    public Id verifiedContactId;
  }

  public class Response {
    @InvocableVariable(
      label='Found'
      description='True only when the policy exists and belongs to the verified contact.'
    )
    public Boolean found = false;

    @InvocableVariable(
      label='Status'
      description='Policy status, e.g. Active or Lapsed.'
    )
    public String status;

    @InvocableVariable(
      label='Product Type'
      description='Product, e.g. Term Life.'
    )
    public String productType;

    @InvocableVariable(
      label='Paid To Date'
      description='Date premiums are paid through.'
    )
    public Date paidToDate;

    @InvocableVariable(
      label='Message'
      description='Plain-language result to relay to the customer.'
    )
    public String message;
  }

  @InvocableMethod(
    label='Get Policy Summary'
    description='Returns status, product and paid-to date for one policy owned by the verified customer. Use when the customer asks about policy status or whether payments are up to date.'
    category='Policy Service'
  )
  public static List<Response> getSummaries(List<Request> requests) {
    List<String> numbers = new List<String>();
    for (Request r : requests) {
      numbers.add(r.policyNumber);
    }
    Map<String, Policy__c> policies = PolicyLookup.byNumber(
      PolicyLookup.normalize(numbers)
    );

    List<Response> responses = new List<Response>();
    for (Request r : requests) {
      Response res = new Response();
      Policy__c p = PolicyLookup.ownedBy(
        policies,
        r.policyNumber,
        r.verifiedContactId
      );
      if (p == null) {
        res.message = NOT_FOUND;
      } else {
        res.found = true;
        res.status = p.Status__c;
        res.productType = p.Product_Type__c;
        res.paidToDate = p.Paid_To_Date__c;
        res.message =
          'Policy ' +
          p.Name +
          ' is ' +
          p.Status__c +
          (p.Paid_To_Date__c == null
            ? '.'
            : ', paid through ' + p.Paid_To_Date__c.format() + '.');
      }
      responses.add(res);
    }
    return responses;
  }
}
