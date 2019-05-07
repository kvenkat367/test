/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: it_promop4 $
 * $Change: 12359786 $
 * $DateTime: 2016/10/21 18:03:30 $
 * $File: //it/portal/htportal/prod/help-62org/app/src/triggers/HTContactTrigger.trigger $
 * $Id: //it/portal/htportal/prod/help-62org/app/src/triggers/HTContactTrigger.trigger#6 $
 * $Revision: #6 $
 */
 
trigger HTContactTrigger on Contact (before insert, before update, after insert, after update, after undelete) {

    HTExternalSharingHelper sharingHelper = new HTExternalSharingHelper();
    Org62ErrorHandlingUtil errorLog = Org62ErrorHandlingUtil.getInstance();	
        
    try {
    	List<Contact> contactsToBeShared = new List<Contact>();
        List<Contact> contactsToCheckAccInactiveOwner = new List<Contact>();

        if (Trigger.isBefore && Trigger.isInsert) {
            
            if(HTEnvConfigBean.getInstance().isContactParentInActiveOwnerFixEnabled()) {
                for (Contact newContact : Trigger.new) {
                    if (sharingHelper.isReceivedFromHelpOrg(newContact.ConnectionReceivedId) ) {
                        contactsToCheckAccInactiveOwner.add(newContact);                 
                    }
                }
                sharingHelper.fixAccountInactiveOwners(contactsToCheckAccInactiveOwner);
            }
        }
    	   
        if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        	
            // create S2S sharing for contacts which are locally created
            // i.e. not received from Help Org via S2S connection
            for (Contact newContact : Trigger.new) {
                if (!sharingHelper.isReceivedFromHelpOrg(newContact.ConnectionReceivedId) ) {
                    contactsToBeShared.add(newContact);                 
                }
            }
          	log('contacts to be shared:' + contactsToBeShared);


        } else if (Trigger.isAfter && Trigger.isUnDelete) {
            // recreate S2S sharing
            // ENABLE CONTACT RESHARING WHEN UNDELETED 
            log('After undelete contact:' + Trigger.new);
            contactsToBeShared.addAll(Trigger.new);
        }
        
        if (contactsToBeShared.size() > 0) {
	        sharingHelper.createSharingForContacts(contactsToBeShared);           
        }           
    } catch (System.Exception ex) {
        //Log any errors
        System.debug(LoggingLevel.Error, 'Help Portal HTContactTrigger failed -' + ex.getMessage());
        errorLog.processException(ex);
	} finally {
        errorLog.logMessage();
	}

	public void log(String message, String objectId) {
		String cName = 'HTContactTrigger';
		System.debug(LoggingLevel.Info, cName + ' - ' + message);
		Org62ErrorHandlingUtil.getInstance().logInfo(cName, 'Help', message, objectId);		
	}
	
	public void log(String message) {
		log(message,'');
	}
}