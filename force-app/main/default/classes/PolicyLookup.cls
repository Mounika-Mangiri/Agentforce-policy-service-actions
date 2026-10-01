/**
 * Loads policies by number in one query (bulk-safe) and enforces that a
 * policy is only returned to the contact who owns it. Runs in user mode.
 */
public with sharing class PolicyLookup {
  public static Map<String, Policy__c> byNumber(Set<String> policyNumbers) {
    Map<String, Policy__c> result = new Map<String, Policy__c>();
    for (Policy__c p : [
      SELECT Id, Name, Status__c, Product_Type__c, Paid_To_Date__c, Contact__c
      FROM Policy__c
      WHERE Name IN :policyNumbers
      WITH USER_MODE
    ]) {
      result.put(p.Name.toUpperCase(), p);
    }
    return result;
  }

  /** Null when missing or owned by someone else, so callers cannot tell which. */
  public static Policy__c ownedBy(
    Map<String, Policy__c> policies,
    String policyNumber,
    Id contactId
  ) {
    if (String.isBlank(policyNumber) || contactId == null) {
      return null;
    }
    Policy__c p = policies.get(policyNumber.trim().toUpperCase());
    return (p != null && p.Contact__c == contactId) ? p : null;
  }

  public static Set<String> normalize(List<String> numbers) {
    Set<String> result = new Set<String>();
    for (String n : numbers) {
      if (String.isNotBlank(n)) {
        result.add(n.trim().toUpperCase());
      }
    }
    return result;
  }
}
