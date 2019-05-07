/* 
 *****************************************************************************************************
 Trigger "SfdcOpportunityTrigger" 

 @Author : Madhu Katragadda
 @since 190.store
 
 ****************************************************************************************************** 
*/

trigger SfdcOpportunityTrigger on Opportunity (before insert, before update, before delete, after insert, after update, after delete) {
    //if the Q2O Sync is creating Opportunity Lines that results in Opportunity Update, bypass this trigger                                          
    // bypass trigger invocation in case of opportunity update via upsell process                          
    if(BaseStatus.byPassTriggerLogic('SfdcOpportunityTrigger')) {
    	return;
    }
    OpportunityBatchConfig__c sfSetting = OpportunityBatchConfig__c.getInstance('SpecialistForecastAutoGenProcess');
    if(sfSetting != null){
        if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWith(sfSetting.APIUserName__c)) {
            return;
        }   
    }     
    //if opportunity is being updated by the specialist forecast Autogen API user or contract expiration API user, bypass trigger execution.
	if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWithIgnoreCase(sfbase.BaseConstants.CONTRACT_EXPIRATION_API_USER) ){
		return;
	} 
	
  	if(Trigger.isBefore && Trigger.isInsert && !LeadConvert.getIsExecutingConvert()) {
      Set<Id> accIdSet = new Set<Id>();
      List<Opportunity> oppToBeProcessed = new List<Opportunity>();
      Map<String, MCServicesDefaultValues__c> defaultMap = MCServicesDefaultValues__c.getAll();
      for(Opportunity o : Trigger.new) {
        o.sfquote__Quote_Exists__c = false;
        if(defaultMap!= null && defaultMap.size()>0 && defaultMap.get(MCServicesOpptyFieldsSyncAPI.OPPTY_RECORD_TYPES).Value__c != null && defaultMap.get(MCServicesOpptyFieldsSyncAPI.OPPTY_RECORD_TYPES).Value__c.contains(o.RecordTypeId)){
          accIdSet.add(o.AccountId);
          oppToBeProcessed.add(o);
        }
                 
      }
      if(accIdSet != null && accIdSet.size() > 0 && oppToBeProcessed != null && oppToBeProcessed.size()>0)
        MCServicesOpptyFieldsSyncAPI.stampMCServicesOpptyFields(oppToBeProcessed,accIdSet,defaultMap);
     }   
  	
  	if(Trigger.isBefore && Trigger.isUpdate && !LeadConvert.getIsExecutingConvert()) {
      List<Opportunity> oppList = new List<Opportunity>();
      for(Opportunity o : Trigger.new) {
          SfdcOpptyTriggerHelper.validateCourtesyOpportunities(Trigger.New,Trigger.oldMap);
          if(o.ForecastCategoryName == BaseConstants.OPPTY_FORCAST_CATEGORY_CLOSED || o.StageName == BaseStatus.OPPTY_STATUS_08_CLOSED){
              oppList.add(o);
          }
      }
      if(oppList!=null && oppList.size()>0)
        SfdcOpptyTriggerHelper.stampSuccessPartnerField(oppList);
    }  	
  	
	if(Trigger.isBefore && (Trigger.isDelete)) {
		SfdcOpptyTriggerHelper.deleteDraftQuotesOnOpptyDeleteOrSetError(Trigger.old,Trigger.oldMap); 		
	}  
	
	if(Trigger.isAfter && (Trigger.isUpdate || Trigger.isInsert)) {
		SfdcOpptyTriggerHelper.splitOpptyAmount(Trigger.New,Trigger.NewMap,Trigger.oldMap,Trigger.isUpdate,Trigger.isInsert); 	
		if(Trigger.isUpdate){
			SfdcOpptyTriggerHelper.unpublishQuotesOnDeadOpportunity(Trigger.New,Trigger.oldMap);
      CopyOpptyProductACVFields.copyACVFieldsOnUpdate(Trigger.oldMap,Trigger.newMap);  // Added by SCH after moving from OpportunityTrigger
		}		
	} 	

}