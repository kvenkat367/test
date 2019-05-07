/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: wchong $
 * $Change: 1470155 $
 * $DateTime: 2010/10/12 12:41:11 $
 * $File: //it/portal/htportal/prod/help-62org/app/src/triggers/HTContactMergeTrigger.trigger $
 * $Id: //it/portal/htportal/prod/help-62org/app/src/triggers/HTContactMergeTrigger.trigger#1 $
 * $Revision: #1 $
 */

trigger HTContactMergeTrigger on Contact (before delete) {
	
	Org62ErrorHandlingUtil errorLog = Org62ErrorHandlingUtil.getInstance();	
    try {
        if (Trigger.isBefore && Trigger.isDelete) { 
            // fire a fake update on the children of contact
            
            // call @future method to do a fake update on the cases so that the reparenting flows via S2S
            List<Case> caseListForUpdate = [SELECT Id from Case Where contactid in :Trigger.old];
            Map<Id,Case> caseMap = new Map<Id,Case>();
            caseMap.putAll(caseListForUpdate);
            
            if (caseMap.keySet().size() > 0) {
               HTExternalSharingHelper.touchCases(caseMap.keySet());    
            }
        
        }
    } catch (System.Exception ex) {
        //Log any errors
        System.debug(LoggingLevel.Error, 'Help Portal HTContactMergeTrigger failed -' + ex.getMessage());
        errorLog.processException(ex);
	} finally {
        errorLog.logMessage();
	}
}