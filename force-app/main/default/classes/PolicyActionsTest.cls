@IsTest
private class PolicyActionsTest {
  @TestSetup
  static void setup() {
    Contact owner = new Contact(FirstName = 'Jamie', LastName = 'Sample');
    Contact other = new Contact(FirstName = 'Morgan', LastName = 'Placeholder');
    insert new List<Contact>{ owner, other };
    insert new List<Policy__c>{
      new Policy__c(
        Name = 'DEMO-TL-100001',
        Status__c = 'Active',
        Product_Type__c = 'Term Life',
        Paid_To_Date__c = Date.newInstance(2026, 9, 30),
        Contact__c = owner.Id
      ),
      new Policy__c(
        Name = 'DEMO-FA-200002',
        Status__c = 'Lapsed',
        Product_Type__c = 'Fixed Annuity',
        Contact__c = other.Id
      )
    };
  }

  private static Id contactId(String lastName) {
    return [SELECT Id FROM Contact WHERE LastName = :lastName LIMIT 1].Id;
  }

  private static GetPolicySummaryAction.Request summaryRequest(
    String policyNumber,
    Id contact
  ) {
    GetPolicySummaryAction.Request r = new GetPolicySummaryAction.Request();
    r.policyNumber = policyNumber;
    r.verifiedContactId = contact;
    return r;
  }

  @SuppressWarnings('PMD.ExcessiveParameterList') // readable test builder
  private static CreateServiceRequestAction.Request caseRequest(
    String policyNumber,
    Id contact,
    String requestType,
    String details
  ) {
    CreateServiceRequestAction.Request r = new CreateServiceRequestAction.Request();
    r.policyNumber = policyNumber;
    r.verifiedContactId = contact;
    r.requestType = requestType;
    r.details = details;
    return r;
  }

  @IsTest
  static void summaryForOwnerIsReturned() {
    List<GetPolicySummaryAction.Response> res = GetPolicySummaryAction.getSummaries(
      new List<GetPolicySummaryAction.Request>{
        summaryRequest(' demo-tl-100001 ', contactId('Sample'))
      }
    );
    Assert.isTrue(res[0].found);
    Assert.areEqual('Active', res[0].status);
    Assert.areEqual(Date.newInstance(2026, 9, 30), res[0].paidToDate);
    Assert.isTrue(res[0].message.contains('DEMO-TL-100001'));
  }

  @IsTest
  static void otherCustomersPolicyLooksNotFound() {
    List<GetPolicySummaryAction.Response> res = GetPolicySummaryAction.getSummaries(
      new List<GetPolicySummaryAction.Request>{
        summaryRequest('DEMO-FA-200002', contactId('Sample')),
        summaryRequest('NO-SUCH-POLICY', contactId('Sample'))
      }
    );
    Assert.isFalse(res[0].found);
    Assert.isFalse(res[1].found);
    Assert.areEqual(res[0].message, res[1].message);
    Assert.isNull(res[0].status);
  }

  @IsTest
  static void bulkSummaryUsesOneQuery() {
    List<GetPolicySummaryAction.Request> reqs = new List<GetPolicySummaryAction.Request>();
    for (Integer i = 0; i < 50; i++) {
      reqs.add(summaryRequest('DEMO-TL-100001', contactId('Sample')));
    }
    Integer before = Limits.getQueries();
    GetPolicySummaryAction.getSummaries(reqs);
    Assert.areEqual(1, Limits.getQueries() - before);
  }

  @IsTest
  static void caseIsCreatedForOwner() {
    Id owner = contactId('Sample');
    List<CreateServiceRequestAction.Response> res = CreateServiceRequestAction.create(
      new List<CreateServiceRequestAction.Request>{
        caseRequest(
          'DEMO-TL-100001',
          owner,
          'Address Change',
          'Moving to a new address next month.'
        )
      }
    );
    Assert.isTrue(res[0].success, res[0].message);
    Case c = [
      SELECT Subject, ContactId, Origin
      FROM Case
      WHERE CaseNumber = :res[0].caseNumber
    ];
    Assert.areEqual('Address Change - DEMO-TL-100001', c.Subject);
    Assert.areEqual(owner, c.ContactId);
  }

  @IsTest
  static void invalidRequestsAreRejectedWithoutDml() {
    Id owner = contactId('Sample');
    List<CreateServiceRequestAction.Response> res = CreateServiceRequestAction.create(
      new List<CreateServiceRequestAction.Request>{
        caseRequest('DEMO-TL-100001', owner, 'Cancel Policy', 'Please cancel'),
        caseRequest('DEMO-TL-100001', owner, 'Other', '   '),
        caseRequest('DEMO-TL-100001', owner, 'Other', 'x'.repeat(2001)),
        caseRequest('DEMO-FA-200002', owner, 'Other', 'Not my policy')
      }
    );
    for (CreateServiceRequestAction.Response r : res) {
      Assert.isFalse(r.success);
      Assert.isNotNull(r.message);
    }
    Assert.isTrue(res[0].message.startsWith('Request type must be one of'));
    Assert.areEqual(GetPolicySummaryAction.NOT_FOUND, res[3].message);
    Assert.areEqual(0, [SELECT COUNT() FROM Case]);
  }
}
