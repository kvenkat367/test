/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: $
 * $Change: $
 * $DateTime: $
 * $File: $
 * $Id: $
 * $Revision: $
 *
 * @author dfebles
 * @since 2011-01
 */
trigger PartnerOrderTrigger on Partner_Order__c (before insert, before update, after update) {

	if (trigger.isBefore) {

		if(trigger.isInsert) {
			// Converts 15 to 18 chars Id
			PartnerOrderUtility.convertIdTo18(trigger.new, '00D');
		}

		if (trigger.isUpdate) {

			Set<Id> provisionedOrActivatedOrderIdSet = new Set<Id>();
			// This list will hold the Partner Orders whose Customer_Account_Id__c field has changed
			List<Partner_Order__c> partnerOrdersToProcessWithOldLogic = new List<Partner_Order__c>();
			List<Partner_Order__c> partnerOrdersToProcessWithNewLogic = new List<Partner_Order__c>();
            //List to hold partner orders which would have been processed by the batch processor (but instead are being process now'd).
            //The way to distinguish these orders from the other orders is whether they have Versioning information or not.
            Map<Id, Partner_Order__c> partnerOrdersWithVersionNumber = new Map<Id, Partner_Order__c>();
			// This list will hold the Partner Orders whose Customer Org Id field has changed
			List<Partner_Order__c> poOrgIdToProcess = new List<Partner_Order__c>();

			for (Integer i = 0; i < trigger.new.size(); i++) {
				Boolean hasInternalStatusChanged = trigger.old[i].Internal_Status__c != trigger.new[i].Internal_Status__c;
				Boolean hasStatusChanged = trigger.old[i].Status__c != trigger.new[i].Status__c;
				Boolean isStatusProvisionedOrActivated = trigger.new[i].Status__c == PartnerOrderDO.PROVISIONED_STATUS || trigger.new[i].Status__c == PartnerOrderDO.ACTIVATED_STATUS;
				if(hasStatusChanged && isStatusProvisionedOrActivated) {
					provisionedOrActivatedOrderIdSet.add(trigger.new[i].Id);
				} else {
					Boolean isFromManualStep = PartnerOrderDO.INVALID_STATUSES_FOR_PROCESS_NOW.contains(trigger.old[i].Internal_Status__c);
					Boolean isVersionOneOrder = trigger.old[i].COA_Version__c == null || trigger.old[i].COA_Version__c.startsWith('1');
					Boolean shouldProcessNow = hasInternalStatusChanged && trigger.new[i].Internal_Status__c == PartnerOrderDO.PROCESS_NOW_INT_STATUS && (!isFromManualStep || isVersionOneOrder);
                    //Checks if order will be processed with old logic
					if( !trigger.new[i].Created_with_new_COA__c ) {
						if (trigger.old[i].Customer_Org_ID__c != trigger.new[i].Customer_Org_ID__c){
							poOrgIdToProcess.add(trigger.new[i]);
						}
						// If the Internal Status has changed to Process Now and the Type is Initial or Add-On, then process the Partner Order
						if (shouldProcessNow) {
						    if (trigger.new[i].Partner_Order_Type__c == PartnerOrderDO.INITIAL_ORDER_TYPE ||
						    	trigger.new[i].Partner_Order_Type__c == PartnerOrderDO.ADD_ON_ORDER_TYPE) {
								partnerOrdersToProcessWithOldLogic.add(trigger.new[i]);
						    } else {
						    	trigger.new[i].addError(Label.PartnerOrderMustBeProcessedManually);
						    }
						}
					} else {
						if (shouldProcessNow){
                            if(PartnerOrderDO.RECALLED_INT_STATUS.equals(trigger.old[i].Internal_Status__c)){
                                trigger.new[i].addError(Label.CannotProcessRecalledPartnerOrders);
                            }else if(PartnerOrderDO.COMPLETED_INT_STATUS.equals(trigger.old[i].Internal_Status__c)){
                                trigger.new[i].addError(Label.CannotProcessCompletedPartnerOrders);
                            }else{
                                if(PartnerOrderUtility.hasVersionNumber(trigger.new[i])){
                                    partnerOrdersWithVersionNumber.put(trigger.new[i].Id, trigger.new[i]);
                                }else{
    							    partnerOrdersToProcessWithNewLogic.add(trigger.new[i]);
                                }
                            }
                        }else{
                        	if (isFromManualStep && trigger.new[i].Internal_Status__c == PartnerOrderDO.PROCESS_NOW_INT_STATUS){
                        		trigger.new[i].addError(Label.PartnerOrderAlreadyProcessed);
                        	}
                        }
					}
				}
			}
			if (poOrgIdToProcess.size() > 0) {
				PartnerOrderUtility.convertIdTo18(poOrgIdToProcess, '00D');
			}
			if (partnerOrdersToProcessWithOldLogic.size() > 0) {
				PartnerOrderUtility pou = new PartnerOrderUtility(partnerOrdersToProcessWithOldLogic);
				pou.processAll();
				// Process possible gacks
				PartnerOrderUtility.processGacks();
			}
			if (partnerOrdersToProcessWithNewLogic.size() > 0) {
				// ------------- CALLS THE PROCESS TO CREATE CONTRACT/ORDERS/OPPTIES IF NEEDED ------------
				PartnerOrderTriggerHandler.partnerOrdersProcessNow(partnerOrdersToProcessWithNewLogic);
			}
			//For new/versioned orders, attempt to execute order processing logic asynchronously by firing off the batch.  If it fails, inform the user and reject update.
            if(!partnerOrdersWithVersionNumber.isEmpty()){
				COA_PartnerOrderProcessor.ProcessResponseNowBatch response = COA_PartnerOrderProcessor.processNowOrdersFromTrigger(partnerOrdersWithVersionNumber);
				if (response.isSuccess) {
					for (Partner_Order__c ord : partnerOrdersWithVersionNumber.values()) {
						ord.Internal_Status__c = PartnerOrderDO.IN_PROCESS_STATUS;
					}
				} else {
					for (Partner_Order__c ord : partnerOrdersWithVersionNumber.values()) {
						ord.addError(response.errorMessage);
					}
				}
            } 
			if(provisionedOrActivatedOrderIdSet.size() > 0) {
				PartnerOrderTriggerHandler.partnerOrdersSetFirstReport(provisionedOrActivatedOrderIdSet);
			}
		}
	}

	if (trigger.isAfter) {
		if (trigger.isUpdate) {

			List<Partner_Order__c> partnerOrdersToProcess = new List<Partner_Order__c>();

			// Verifies that the Status__c has changed
			for (Integer i = 0; i < trigger.new.size(); i++) {
				if((trigger.old[i].Status__c != trigger.new[i].Status__c)){
					partnerOrdersToProcess.add(trigger.new[i]);
				}
			}

			// Send a message to Partner Org in order to synchronize the status of the Partner Order
			if (partnerOrdersToProcess.size() > 0) {
				Map<String, List<Partner_Order__c>> partnerOrdersByEmail = new Map<String, List<Partner_Order__c>>();
				for (Partner_Order__c po : partnerOrdersToProcess){
					if (partnerOrdersByEmail.containsKey(po.X62Org_To_Partner_Org_Email__c)){
						partnerOrdersByEmail.get(po.X62Org_To_Partner_Org_Email__c).add(po);
					}else{
						partnerOrdersByEmail.put(po.X62Org_To_Partner_Org_Email__c, new List<Partner_Order__c>{po});
					}

				}
				for (String email : partnerOrdersByEmail.keySet()){
					PartnerOrderUtility.X62OrgToPartnerOrgEmail = null;
					PartnerOrderUtility.sendMessageToPartnerOrg(partnerOrdersByEmail.get(email), null, null);
				}
			}
		}
	}

}