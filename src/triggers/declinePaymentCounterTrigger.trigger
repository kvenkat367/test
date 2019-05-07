trigger declinePaymentCounterTrigger on Contract (before update) 
{
    Integer index=0;
     
    List<Contract> contractList = new List<Contract>();
   
    for(Contract con : trigger.new)
    {
        if(trigger.new[index].sfbase__PaymentToken__c != trigger.old[index].sfbase__PaymentToken__c)
        {
            if(con.sfbase__PaymentToken__c != null && con.DeclinePaymentsCounter__c == 2)
            {
                system.debug('The Payment token is coming as ****************************'+con.sfbase__PaymentToken__c);
                system.debug('The decline payment counter is coming as *******************'+con.DeclinePaymentsCounter__c);
                con.DeclinePaymentsCounter__c = 1;                          
            }
        }     
        index++;       
    }       
}