/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: wchong $
 * $Change: 1470155 $
 * $DateTime: 2010/10/12 12:41:11 $
 * $File: //it/portal/htportal/prod/help-62org/app/src/triggers/HTAccountMergeTrigger.trigger $
 * $Id: //it/portal/htportal/prod/help-62org/app/src/triggers/HTAccountMergeTrigger.trigger#1 $
 * $Revision: #1 $
 */

trigger HTAccountMergeTrigger on Account (before delete) {
	// cannot automatically merge an unlimited number of contacts and cases
	// set maximums for each object that can be processed by this trigger
	// if the maximums are reached, send an email to notify dev that manual intervention is necessary
	final Integer MAX_CONTACT_COUNT = 8000;
	final Integer MAX_CASE_COUNT = 1000;

	Org62ErrorHandlingUtil errorLog = Org62ErrorHandlingUtil.getInstance();	
    try {
        if (Trigger.isBefore && Trigger.isDelete) {
            
            // call @future method to do a fake update on the contacts so that the reparenting flows via S2S
            // Cases under contacts would reparented automatically on Org 62 side
            // Case under contacts on Help Org side would be updated as part of contact update trigger
            // addressing scalability by notifying dev that a manual merge is required
            log('in before delete');
            List<Contact> contactListForUpdate = [SELECT Id from Contact Where Accountid in :Trigger.old LIMIT :MAX_CONTACT_COUNT];
            Map<Id,Contact> contactMap = new Map<Id,Contact>();
            contactMap.putAll(contactListForUpdate);
            
            
            log('Accounts:' + Trigger.old);

            log('contactMap size:' + contactMap.size());
            
            if (contactMap.keySet().size() >= MAX_CONTACT_COUNT) {
            	// send email with pertinent details about merge
            	String body = 'HTAccountMergeTrigger affect cases exceeded ' + MAX_CONTACT_COUNT + ' for possible victim Account in merge. id list = ' + Trigger.old;
            	HTExternalSharingHelper.notifyDev('maximum contact size reached on Account Before Delete Trigger', body);
            	// TODO: consider writing to a queue for further processing
            } else if (contactMap.keySet().size() > 0) {
	        	log('Touching Contacts:' + contactMap);
            	HTExternalSharingHelper.touchContactsForAccountMerge(contactMap.keySet());    
            }
            
            // Case under contact would automatically be updated in Help Portal org
            // Only update cases which does not have contact but has an associated account which got merged with the new account.
            List<Case> caseListForUpdate = [SELECT Id from Case Where Accountid in :Trigger.old and contactid = null LIMIT :MAX_CASE_COUNT];
            Map<Id,Case> caseMap = new Map<Id,Case>();
            caseMap.putAll(caseListForUpdate);

            log('caseMap size:' + caseMap.size());
            
            if (caseMap.keySet().size() >= MAX_CASE_COUNT) {
            	// send email with pertinent details about merge
            	String body = 'HTAccountMergeTrigger affected cases exceeded ' + MAX_CASE_COUNT + ' for possible victim Account in merge. id list = ' + Trigger.old;
            	HTExternalSharingHelper.notifyDev('maximum case size reached on Account Before Delete Trigger', body);
            	// TODO: consider writing to a queue for further processing
            } else if (caseMap.keySet().size() > 0) {
	           log('Touching Cases:' + contactMap);
               HTExternalSharingHelper.touchCases(caseMap.keySet());    
            }
        } else if (Trigger.isAfter && Trigger.isDelete) {
        	Map<Id,Id> losersAndWinners = new Map<Id,Id>();
        	Set<Id> winners = new Set<Id>();
  			for (Account a : Trigger.old) { 
  				if (a.MasterRecordId != null) {
  					losersAndWinners.put(a.Id,a.MasterRecordId);
  					winners.add(a.MasterRecordId);
  				}
  			}
  			log('After Delete merge losers and winners: ' + losersAndWinners);
  			
            Integer contactCount = [SELECT count() from Contact Where Accountid in :Trigger.old LIMIT :MAX_CONTACT_COUNT];
            Integer caseCount = [SELECT count() from Case Where Accountid in :Trigger.old and contactid = null LIMIT :MAX_CASE_COUNT];
            
            log('contactCount: ' + contactCount + ' caseCount: '+ caseCount);
            
  			if (contactCount >= MAX_CONTACT_COUNT || caseCount >= MAX_CASE_COUNT) {
	  			String body = 'HTAccountMergeTrigger after delete losers and winners map: ' + losersAndWinners;
	            HTExternalSharingHelper.notifyDev('after delete losers and winners', body);
  			}  			
        }   

    } catch (System.Exception ex) {
        //Log any errors
        System.debug(LoggingLevel.Error, 'Help Portal HTAccountMergeTrigger failed -' + ex.getMessage());
        errorLog.processException(ex);
	} finally {
        errorLog.logMessage();
	}
	
	public void log(String message, String objectId) {
		String cName = 'HTAccountMergeTrigger';
		System.debug(LoggingLevel.Info, cName + ' - ' + message);
		Org62ErrorHandlingUtil.getInstance().logInfo(cName, 'Help', message, objectId);		
	}
	
	public void log(String message) {
		log(message,'');
	}
}