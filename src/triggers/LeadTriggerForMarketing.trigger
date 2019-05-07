Trigger LeadTriggerForMarketing on Lead(before insert, before update ){
	
	if(Trigger.isBefore){
		if(Trigger.isInsert ){
			LeadTriggerForMarketingHandler.populateIntialMarketAssigned(Trigger.new, Trigger.OldMap,true);
		}
		if(Trigger.isUpdate){
			LeadTriggerForMarketingHandler.populateIntialMarketAssigned(Trigger.new, Trigger.OldMap,false);
		}

	}
}