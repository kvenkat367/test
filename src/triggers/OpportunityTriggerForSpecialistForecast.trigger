/* 
 *****************************************************************************************************
 Trigger "OpportunityTriggerForSpecialistForecast" 

 @Author : Madhu Katragadda
 @since 190.store
 
 ****************************************************************************************************** 
*/

trigger OpportunityTriggerForSpecialistForecast on Opportunity (before update, before delete) {
	//if the Q2O Sync is creating Opportunity Lines that results in Opportunity Update, bypass this trigger
	// bypass trigger invocation in case of opportunity update via upsell process
     if(BaseStatus.byPassTriggerLogic('OpportunityTriggerForSpecialistForecast') || (UserInfo.getUserName() != null && UserInfo.getUserName().startsWithIgnoreCase('it-partnerportal@salesforce.com'))) {
        return;
    }
    //if opportunity is being updated by the specialist forecast user, bypass trigger execution.
    OpportunityBatchConfig__c sfSetting = OpportunityBatchConfig__c.getInstance('SpecialistForecastAutoGenProcess');
	if(sfSetting != null){
		if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWith(sfSetting.APIUserName__c)) {
	        return;
	    }   
    }
	public static Map<String,Id> OPPTY_RT_MAP_BY_NAME = BaseRecordTypeUtil.getActiveRecordTypes(BaseRecordTypeUtil.OPPORTUNITY_RECORD_TYPE);
    Set<Id> opptyIds = new Set<Id>();
 	if(Trigger.isBefore && (Trigger.isUpdate)) {
		for (Opportunity opp: Trigger.New) {
			if(Trigger.isUpdate){
				//this is only valid for New Business / Add-On record types
				if(opp.RecordTypeId == OPPTY_RT_MAP_BY_NAME.get(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_NEWBIZ_ADDON) || opp.RecordTypeId == OPPTY_RT_MAP_BY_NAME.get(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_NEWBIZ_ADDON_LOCKED) ){
					Opportunity oldOpp = Trigger.oldMap.get(opp.Id);
					if(oldOpp.Amount != opp.Amount ||
			 			oldOpp.CloseDate != opp.CloseDate ||
			 			oldOpp.StageName != opp.StageName ||
			 			oldOpp.ForecastCategoryName != opp.ForecastCategoryName ){
						opp.sfbase__AutoGenerateSpecialistForecast__c = true;
					}
				}
			}
		}		
	}
}