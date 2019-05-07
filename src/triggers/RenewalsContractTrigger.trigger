/**
 * @author rsubramani, auzzaman
 * @since store.162
 *
 */

trigger RenewalsContractTrigger on Contract bulk(before insert, before update, after update, after insert) {
	//If the update to the contract is a result of another related object, then the below statement will yield true
    if(sfbase.OrderManagementUtils.canBypassTriggerExecution('Contract')) {
		return;
	}
	private final String CONVERSION_LOGIN = 'conversion_api@salesforce.com';
	private final String DUNNING_USER = 'billing@salesforce.com';
	if(UserInfo.getUserName() != null && (UserInfo.getUserName().startsWithIgnoreCase(CONVERSION_LOGIN) || UserInfo.getUserName().startsWithIgnoreCase(DUNNING_USER) )){
		return;
	}
	// If it is the VAT API user updating the Contract fields after the VIES call then bypass trigger execution.
	if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWithIgnoreCase(BaseConstants.VAT_API_USER)){
		return;
	}

    //The contract trigger gets called when the order item available qty/renewal qty is updated as we need to update the coso update flag.
    //In such a scenario we dont want to execute the trigger below as it has no relevant functionality.
    if(OrderManagementUtil.getIsUpdateFromOrderItemTrigger()) {
        return;
    }
    String userLogin = UserInfo.getUserName();
    if(userLogin.startsWith(RenewalOpptyUtil.DEAL_SUMMARY_USER_NAME)) {
		return;
	}
    //Create Deal Helper Instance        
    DealRelationshipHelper dealHelper = new DealRelationshipHelper();

    Id opptyLockRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_RENEWAL_ATTRITION_LOCKED);
    Id mcOpptyLockRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_MC_NEWBIZ_RENEWAL_ATTRITION_LOCKED);
    Id opptyRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_RENEWAL_ATTRITION);        
    Id mcOpptyRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_MC_NEWBIZ_RENEWAL_ATTRITION);
    Id conSalesRTId = RenewalOpptyUtil.getContractRTIdByName(BaseRecordTypeUtil.CONTRACT_RECORD_TYPE_SALES);
    Id conSrvsRTId = RenewalOpptyUtil.getContractRTIdByName(BaseRecordTypeUtil.CONTRACT_RECORD_TYPE_SERVICES);
    Id conJPRTId = RenewalOpptyUtil.getContractRTIdByName(BaseRecordTypeUtil.CONTRACT_RECORD_TYPE_JP_LICENSE);

    if(Trigger.isUpdate && Trigger.isBefore) {
        if(dealHelper.isFeatureEnabledForContract()) {    
            // Any change in contract .
            List<SObject> contracts = dealHelper.getChangeList(Trigger.OldMap,Trigger.new,dealHelper.getContractDealFields());

            //Prevent update for CEOs Created Deals 
            dealHelper.lockContracts(Trigger.oldMap,contracts);
        }
        //We dont change the Status/Renewal oppty indicator in case of AR user. Need to be re-evaluated if there are any changes
		Set<Id> changedDeals = new Set<Id>();
		Map<Id, Contract> changedContracts = new Map<Id, Contract>();
		Map<Id, sfbase__DealRelationship__c> deals = new Map<Id, sfbase__DealRelationship__c>();
        if(!BaseStatus.autoRenewalProcessRunning && ! userLogin.startsWith(eimUtils.RENEWAL_USER_NAME)) {
	        for(Contract ctr : Trigger.new) {
	        	if(!OrderManagementUtil.IS_QUOTE_CONVERSION_CONTEXT) {
					RenewalOpptyUtil.checkSameDealForPriorAndNext(ctr);
					RenewalOpptyUtil.populateChangedDealsForContract(ctr, Trigger.oldMap.get(ctr.Id), changedDeals, changedContracts);
				}
	            if(ctr.Status =='Activated' && (Trigger.oldMap.get(ctr.Id).Status != 'Activated')) {
	            	// Bug: W-952192
					if('Month-to-Month'.equals(ctr.sfbase__ContractTreatment__c)) {
						ctr.sfbase__RenewalOpportunityIndicator__c = 'Never Create';
					} else {
                        system.debug(ctr.RecordTypeId +'  ***  '+conSalesRTId+'  ***  '+ctr.sfbase__ContractType__c);
                        if((ctr.sfbase__PriceBookCategory__c != 'Subscription' ||
		                        !(ctr.sfbase__ContractType__c =='New' || ctr.sfbase__ContractType__c =='New - Upgrade'||ctr.sfbase__ContractType__c =='New - Downgrade' || ctr.sfbase__ContractType__c =='Renewal'|| ctr.sfbase__ContractType__c =='Renewal - Upgrade' || ctr.sfbase__ContractType__c =='Renewal - Downgrade') ||
                                !(ctr.RecordTypeId == conSalesRTId || ctr.RecordTypeId == conJPRTId) )&& !(ctr.RecordTypeId == conSalesRTId && ctr.sfbase__ContractType__c == 'Services')){
                                system.debug('***');
                               
		                    ctr.sfbase__RenewalOpportunityIndicator__c='Does Not Meet Criteria';
		                }
                        
                        
		                else{
		                    ctr.sfbase__RenewalOpportunityIndicator__c='Evaluate';
		                    ctr.sfbase__RenewalOptyCreationDays__c =9999;
		                }
					}
	            }
	            if(Trigger.oldMap.get(ctr.Id).sfbase__RenewalOpportunityIndicator__c =='Does Not Meet Criteria' && ctr.sfbase__RenewalOpportunityIndicator__c != Trigger.oldMap.get(ctr.Id).sfbase__RenewalOpportunityIndicator__c) {
                    if((ctr.sfbase__PriceBookCategory__c != 'Subscription' ||
	                        ctr.Status !='Activated' ||
                                !(ctr.sfbase__ContractType__c =='New' || ctr.sfbase__ContractType__c =='New - Upgrade'||ctr.sfbase__ContractType__c =='New - Downgrade' || ctr.sfbase__ContractType__c =='Renewal'|| ctr.sfbase__ContractType__c =='Renewal - Upgrade' || ctr.sfbase__ContractType__c =='Renewal - Downgrade') ||
                                !(ctr.RecordTypeId == conSalesRTId || ctr.RecordTypeId == conJPRTId) )&& !(ctr.RecordTypeId == conSalesRTId && ctr.sfbase__ContractType__c == 'Services')){
                                system.debug('***');
                               
	                    ctr.addError(Label.REN_ERR_OPPTY_INDICATOR);
	            }
                        
                }
        	} // end of for

                    
        	if(!changedDeals.isEmpty()) {
        		deals = new Map<Id, sfbase__DealRelationship__c>([SELECT sfbase__status__c FROM sfbase__DealRelationship__c WHERE Id IN: changedDeals]);
	        	for(Contract ctr : Trigger.new) {
					RenewalOpptyUtil.addErrorOrUpdateDeal(ctr, Trigger.oldMap.get(ctr.Id), deals, UserInfo.getProfileId());
		        }
			}
        	if(!changedContracts.isEmpty()) {
	        	RenewalOpptyUtil.validateCommissionStatusForDeal(changedContracts);
	        }
        }

        Map<Id, Opportunity> opptysToUpdate = new Map<Id, Opportunity>();
        Map<Id,Contract> ctrMap = new Map<Id, Contract>();
        OpportunityContract__c[] opptyCtr;
        

        for(Contract ctr : Trigger.new){
            if(ctr.AutoRenewCode =='Yes' && !(ctr.StatusCode=='Terminated')){
                ctrMap.put(ctr.Id, ctr);
            }
        }
        if((BaseStatus.autoRenewalProcessRunning || userLogin.startsWith(eimUtils.RENEWAL_USER_NAME)) && !(ctrMap==null || ctrMap.isEmpty())){
            opptyCtr = [Select Id,ContractId__c,OpportunityId__c,OpportunityId__r.StageName,OpportunityId__r.sfbase__Contract_EndDate__c, OpportunityId__r.RecordTypeId, OpportunityId__r.CloseDate,OpportunityId__r.sfquote__Quote_Exists__c,OpportunityId__r.sfbase__PriorContractPrimary__c 
                        From OpportunityContract__c 
                        Where  ContractId__c IN: ctrMap.keySet() 
                        AND OpportunityId__r.sfbase__PriorContractPrimary__c IN: ctrMap.keySet() 
                        AND (OpportunityId__r.RecordTypeId =: opptyRTId OR OpportunityId__r.RecordTypeId =: mcOpptyRTId)
                        ];

            for(OpportunityContract__c oppCtr : opptyCtr) {
                if(!ctrMap.containsKey(oppCtr.OpportunityId__r.sfbase__PriorContractPrimary__c)) {
                    continue;
                }
                Contract ctr= ctrMap.get(oppCtr.ContractId__c);
                if(ctr !=null){
                	if(ctr.AutoRenewCode =='Yes' && !(ctr.StatusCode=='Terminated') && (oppCtr.OpportunityId__r.sfbase__Contract_EndDate__c < ctr.EndDate))  {
                		//do not flip the status(and other fields) on the Opportunity if it is Dead - Duplicate or Dead Attrition already
                		//else update it and set it to closed and set other flags on the Opportunity
 						if(!(oppCtr.OpportunityId__r.StageName=='Dead - Duplicate' || oppCtr.OpportunityId__r.StageName=='Dead Attrition')){
                            Opportunity updateOpty;
                            if(oppCtr.OpportunityId__r.RecordTypeId == mcOpptyRTId)
                                updateOpty =new Opportunity(Id=oppCtr.OpportunityId__c,CloseDate=ctr.EndDate.addMonths(-ctr.RenewalTerm),StageName='05 Closed',sfbase__ForecastedContractTerm__c=ctr.RenewalTerm,RecordTypeId=mcOpptyLockRTId,sfbase__OpsoOverride__c=true,sfbase__IsAutoRenewed__c=true);
                            else 
                                updateOpty =new Opportunity(Id=oppCtr.OpportunityId__c,CloseDate=ctr.EndDate.addMonths(-ctr.RenewalTerm),StageName='05 Closed',sfbase__ForecastedContractTerm__c=ctr.RenewalTerm,RecordTypeId=opptyLockRTId,sfbase__OpsoOverride__c=true,sfbase__IsAutoRenewed__c=true);
                            
                    		opptysToUpdate.put(oppCtr.OpportunityId__c,updateOpty);
                    	} 	
                    	ctr.sfbase__HasRenewalOpportunity__c=false;
                    	ctr.sfbase__COSOUpdateRequired__c=true;
                	}
                }
            }
        }

        if(opptysToUpdate.size() > 0) {
            List<String[]> gacks = new List<String[]>();
            try {
                update opptysToUpdate.values();
            } catch(System.DmlException ex) {
                Integer i;
                for(i=ex.getNumDml() - 1; i>=0; i--) {
                    //Get errored out Opptys's id
                    Opportunity badOppty = opptysToUpdate.values().get(ex.getDmlIndex(i));
                    //Add to bad oppty id set with message for display/api
                    gacks.add(new String[] {'Error When updating Renewal Opportunity for Contract '+badOppty.sfbase__PriorContractPrimary__c, ex.getDmlMessage(i)});
                    //Remove any problematic Opptys from the updated list
                    opptysToUpdate.remove(ex.getDmlId(i));
                }
                if(opptysToUpdate.size() > 0) {
                    //Try again to update with good ones
                    update opptysToUpdate.values();
                }
                RenewalOpptyUtil.processGacks(gacks);
            } catch(Exception ex){
                gacks.add(new String[] {'Error When updating Renewal Opportunity for Contract ',ex.getMessage()});
                RenewalOpptyUtil.processGacks(gacks);
            }
        }

    }

    // Any change in Prev/Next Deal - set to Ready feature 
    if(dealHelper.isFeatureEnabledForContract()) {    
 
        if(Trigger.isUpdate && Trigger.isAfter ) {
            // Any change in contract .
            List<SObject> contracts = dealHelper.getChangeList(Trigger.OldMap,Trigger.new,dealHelper.getContractDealFields());
           
            //Any update happen to Contract Deal Prior/Next is in Calculations Completed Stage, go back to Ready
            dealHelper.setDealReady(Trigger.oldMap,contracts);
        }
    }
        
    if(Trigger.isUpdate && Trigger.isAfter && !BaseStatus.autoRenewalProcessRunning && !userLogin.startsWith(eimUtils.RENEWAL_USER_NAME)) {
        OpportunityContract__c[] opptyCtr = [Select Id,ContractId__c,OpportunityId__c,OpportunityId__r.OwnerId,OpportunityId__r.RecordTypeId,OpportunityId__r.StageName,OpportunityId__r.CloseDate,OpportunityId__r.sfquote__Quote_Exists__c,OpportunityId__r.sfbase__PriorContractPrimary__c From OpportunityContract__c Where  ContractId__c IN :Trigger.new AND (OpportunityId__r.RecordTypeId =: opptyRTId OR OpportunityId__r.RecordTypeId =: mcOpptyRTId)];
        Map<Id, Opportunity> opptysToUpdate = new Map<Id, Opportunity>();
        Map<Id,Contract> ctrMap = new Map<Id, Contract>();
        Map<Id,Id> opptyCreateTask =new Map<Id,Id>();
        List<Id> updateOPSOs =new List<Id>();
        List<sfbase__OpportunityProductSummary__c> updatedOpsos =new List<sfbase__OpportunityProductSummary__c>();
        Map<Id, List<OpportunityContract__c>> contractToAsscMap = new Map<Id, List<OpportunityContract__c>>();
        for(Contract ctr : Trigger.new){
            ctrMap.put(ctr.Id, ctr);
        }
        
        for(OpportunityContract__c oppCtr : opptyCtr) {
            if(contractToAsscMap.containsKey(oppCtr.ContractId__c)) {
                contractToAsscMap.get(oppCtr.ContractId__c).add(oppCtr);
            } else {
                contractToAsscMap.put(oppCtr.ContractId__c, new List<OpportunityContract__c>{oppCtr});
            }
            if(!ctrMap.containsKey(oppCtr.OpportunityId__r.sfbase__PriorContractPrimary__c)) {
                continue;
            }
            Contract ctr= ctrMap.get(oppCtr.ContractId__c);
            //If renewal oppty and stage is closed, we dont want to perform any updates
            if((oppCtr.OpportunityId__r.RecordTypeId == opptyRTId || oppCtr.OpportunityId__r.RecordTypeId == mcOpptyRTId || oppCtr.OpportunityId__r.RecordTypeId == opptyLockRTId || oppCtr.OpportunityId__r.RecordTypeId == mcOpptyLockRTId)
            	&& (oppCtr.OpportunityId__r.StageName=='05 Closed'|| oppCtr.OpportunityId__r.StageName=='Dead - Duplicate' || oppCtr.OpportunityId__r.StageName=='Dead Attrition')){
				continue;			
			}
			Contract oldContract = Trigger.oldMap.get(ctr.Id);
			if(oldContract == null) {
				continue;
			}
			if(ctr.sfbase__CourtesyRenewalStartDate__c != null) {
				RenewalOpptyUtil.updateOpptyStageName(opptysToUpdate, oppCtr.OpportunityId__c, 'Courtesy');
			} else if((oldContract.StatusCode != ctr.StatusCode || oldContract.sfbase__ContractType__c != ctr.sfbase__ContractType__c) &&
					ctr.StatusCode == 'Activated' && (ctr.sfbase__ContractType__c == 'Courtesy Contract' || ctr.sfbase__ContractType__c == 'Courtesy Renewal')) {
				RenewalOpptyUtil.updateOpptyStageName(opptysToUpdate, oppCtr.OpportunityId__c, 'Courtesy');
			} else if((oldContract.StatusCode != ctr.StatusCode || oldContract.sfbase__RenewalStatus__c != ctr.sfbase__RenewalStatus__c) &&
					(ctr.StatusCode == 'Terminated' || ctr.StatusCode == 'Expired')) {
				if(ctr.sfbase__RenewalStatus__c =='Did not renew' || ctr.sfbase__RenewalStatus__c == null) {
					RenewalOpptyUtil.updateOpptyStageName(opptysToUpdate, oppCtr.OpportunityId__c, 'Dead Attrition');
					updateOPSOs.add(oppCtr.OpportunityId__c);
				} else if(ctr.sfbase__RenewalStatus__c=='Contract Replacement') {
					RenewalOpptyUtil.updateOpptyStageName(opptysToUpdate, oppCtr.OpportunityId__c, 'Dead - Duplicate');
					updateOPSOs.add(oppCtr.OpportunityId__c);
				} else if(ctr.sfbase__RenewalStatus__c=='Renewed on Other Contract') {
					RenewalOpptyUtil.updateOpptyStageName(opptysToUpdate, oppCtr.OpportunityId__c, '05 Closed');
				}
			}
			if(ctr.StatusCode=='Terminated' && ctr.sfbase__RenewalStatus__c=='Renewed on Other Contract' && oppCtr.OpportunityId__r.sfquote__Quote_Exists__c) {
				opptyCreateTask.put(oppCtr.OpportunityId__c,oppCtr.OpportunityId__r.OwnerId);

			}
        }

        if(opptyCreateTask.size() >0){
            RenewalOpptyUtil opptyProcess = new RenewalOpptyUtil();
            opptyProcess.createTask(opptyCreateTask);
        }

        if(updateOPSOs.size() >0){
            RenewalOpptyUtil opptyProcess = new RenewalOpptyUtil();
            updatedOpsos=opptyProcess.opsosToUpdate(updateOPSOs);
        }

        List<OpportunityContract__c> updatedOpptyContractAsscList = new List<OpportunityContract__c>();
        //We dont change the AR code/Renewal Term in case of AR user. Need to be re-evaluated if there are any changes
        for(Contract contract : Trigger.new ){
            List<OpportunityContract__c> opptyCtrAsscList = contractToAsscMap.get(contract.Id);
            if(opptyCtrAsscList != null && !opptyCtrAsscList.isEmpty()) {
                if(Trigger.oldMap.get(contract.Id).AutoRenewCode != contract.AutoRenewCode) {
                    for(OpportunityContract__c opptyContractAssc : opptyCtrAsscList) {
                        opptyContractAssc.OPSOUpdateRequired__c = true;
                        if(opptyContractAssc.OpportunityId__r.sfbase__PriorContractPrimary__c == contract.Id) {
                            RenewalOpptyUtil.updateOpptyForecastedTerm(opptysToUpdate, opptyContractAssc.OpportunityId__c, contract);
                        }
                        updatedOpptyContractAsscList.add(opptyContractAssc);
                    }
                } else if(Trigger.oldMap.get(contract.Id).RenewalTerm != contract.RenewalTerm) {
                    for(OpportunityContract__c opptyContractAssc : opptyCtrAsscList) {
                        if(opptyContractAssc.OpportunityId__r.sfbase__PriorContractPrimary__c == contract.Id) {
                            RenewalOpptyUtil.updateOpptyForecastedTerm(opptysToUpdate, opptyContractAssc.OpportunityId__c, contract);
                        }
                    }
                }
            }
        }
        
        if(updatedOpsos.size() > 0) {
            List<String[]> gacks = new List<String[]>();
            try {
                update updatedOpsos;
            } catch(System.DmlException ex) {
                Integer i;
                for(i=ex.getNumDml() - 1; i>=0; i--) {
                    //Get errored out opso id
                    sfbase__OpportunityProductSummary__c badOpso = updatedOpsos.get(ex.getDmlIndex(i));
                    //Add to bad opso id set with message for display/api
                    gacks.add(new String[] {'Error when updating Opportunity product summaries for Contract '+badOpso.sfbase__Opportunity__r.sfbase__PriorContractPrimary__c, ex.getDmlMessage(i)});
                    //Remove any problematic Opsos from the updated list
                    updatedOpsos.remove(ex.getDmlIndex(i));
                }
                if(updatedOpsos.size() > 0) {
                    //Try again to update with good ones
                    update updatedOpsos;
                }
                RenewalOpptyUtil.processGacks(gacks);
            } catch(Exception ex){
				gacks.add(new String[] {'Error when updating Opportunity product summaries for Contract', ex.getMessage()});
                RenewalOpptyUtil.processGacks(gacks);
            }
        }        

        if(opptysToUpdate.size() > 0) {
            List<String[]> gacks = new List<String[]>();
            try {
                update opptysToUpdate.values();
            } catch(System.DmlException ex) {
                Integer i;
                for(i=ex.getNumDml() - 1; i>=0; i--) {
                    //Get errored out Opptys's id
                    Opportunity badOppty = opptysToUpdate.values().get(ex.getDmlIndex(i));
                    //Add to bad oppty id set with message for display/api
                    gacks.add(new String[] {'Error When updating Renewal Opportunity for Contract '+badOppty.sfbase__PriorContractPrimary__c, ex.getDmlMessage(i)});
                    //Remove any problematic Opptys from the updated list
                    opptysToUpdate.remove(ex.getDmlId(i));
                }
                if(opptysToUpdate.size() > 0) {
                    //Try again to update with good ones
                    update opptysToUpdate.values();
                }
                RenewalOpptyUtil.processGacks(gacks);
            } catch(Exception ex){
                gacks.add(new String[] {'Error When updating Renewal Opportunity for Contract ',ex.getMessage()});
                RenewalOpptyUtil.processGacks(gacks);
            }
        }

        if(updatedOpptyContractAsscList.size() > 0) {
            Map<Id, String> badOpptyCtrAsscMap = new Map<Id, String>();
            try {
                //Update opptyContractAssc
                update updatedOpptyContractAsscList;
            } catch(System.DmlException ex) {
                Integer i;
                for(i=ex.getNumDml() - 1; i>=0; i--) {
                    badOpptyCtrAsscMap.put(updatedOpptyContractAsscList.get(ex.getDmlIndex(i)).ContractId__c, ex.getDmlMessage(i));
                    //Remove any problematic opptyContractAsscs from the updated list
                    updatedOpptyContractAsscList.remove(ex.getDmlIndex(i));
                }
                if(updatedOpptyContractAsscList.size() > 0) {
                    //Try again to update with good ones
                    update updatedOpptyContractAsscList;
                }
                //add error to opsos where its oppty updates have failed
                for(Contract contract : System.Trigger.New){
                    if(badOpptyCtrAsscMap.containsKey(contract.Id)) {
                        contract.addError('Update to Oppportunity-Contract Association ' + contractToAsscMap.get(contract.Id) + ' for the Contract ' + contract.Id +
                                            ' failed with the following error: ' + badOpptyCtrAsscMap.get(contract.Id));
                    }
                }
            }
        }


        if(RenewalOpptyUtil.getUpdatedDeals().size() > 0) {
            List<String[]> gacks = new List<String[]>();
            try {
                update RenewalOpptyUtil.getUpdatedDeals().values();
            } catch(System.DmlException dex) {
                Integer i;
                for(i = dex.getNumDml() - 1; i >= 0; i--) {
                    // Get errored out deal id
                    sfbase__DealRelationship__c badDeal = RenewalOpptyUtil.getUpdatedDeals().get(dex.getDmlId(i));
                    // Add to bad deal id set with message for display/api
                    gacks.add(new String[] {'Error when updating Contract for Deal Relationship ' + badDeal.Id, dex.getDmlMessage(i)});
                    // Remove any problematic deals from the updated list
                    RenewalOpptyUtil.getUpdatedDeals().remove(dex.getDmlId(i));
                }
                if(!RenewalOpptyUtil.getUpdatedDeals().isEmpty()) {
                    // Try again to update with good ones
                    update RenewalOpptyUtil.getUpdatedDeals().values();
                }
                RenewalOpptyUtil.processGacks(gacks);
            } catch(Exception ex){
				gacks.add(new String[] {'Error when updating Contract for Deal Relationship ', ex.getMessage()});
                RenewalOpptyUtil.processGacks(gacks);
            }
        }
    }
}