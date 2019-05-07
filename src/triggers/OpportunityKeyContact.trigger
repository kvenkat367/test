trigger OpportunityKeyContact on Opportunity (before insert, before update){

    OpportunityKeyContactClass KeyContacts = new OpportunityKeyContactClass(trigger.new);   

}