/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: it_promop4 $
 * $Change: 12359786 $
 * $DateTime: 2016/10/21 18:03:30 $
 * $File: //it/portal/htportal/prod/help-62org/app/src/triggers/HTAccountTrigger.trigger $
 * $Id: //it/portal/htportal/prod/help-62org/app/src/triggers/HTAccountTrigger.trigger#7 $
 * $Revision: #7 $
 */

trigger HTAccountTrigger on Account (after insert, before update, after update, after undelete, before delete) {
	public final String S2S_USERTYPE = 'PartnerNetwork';
	
	Set<String> bypassUserIds = HTEnvConfigBean.getInstance().getAccountTriggerByPassUserIds();
	if(bypassUserIds.contains(UserInfo.getUserId())) {
		return;
	}

    HTExternalSharingHelper sharingHelper = new HTExternalSharingHelper();
    Org62ErrorHandlingUtil errorLog = Org62ErrorHandlingUtil.getInstance(); 
    public static Boolean SKIP_ACCOUNT_SHARING_TO_HELP_ORG = false;
    
    try {
    	
        List<Account> accountsToBeShared = new List<Account>();
        
        if(Trigger.isBefore && Trigger.isUpdate && !HTEnvConfigBean.getInstance().blockAccountNameUpdateByS2S()) {
        	String userType = UserInfo.getUserType();
         	if (userType == S2S_USERTYPE) {
	        	for (Account newAccount : Trigger.new) {

	        		Account oldAccount = Trigger.oldMap.get(newAccount.Id);
	        		//This will make sure DF org does not override the Account Name in org62. This is needed because Org62 name 
	        		//updates are not flowing to H&T and everytime a portal user logs into portal there is an account update happpening
	        		// which is overrding the account name change is org62
					if (!newAccount.Name.equals(oldAccount.Name)) {
						// TODO: possibly leverage CaseHistory?
						newAccount.Name = oldAccount.Name;					
					}
	        	}
        	}
         	
         	return;
        	
        }
        
        
        if (Trigger.isAfter && Trigger.isInsert) {
            // create S2S sharing for accounts which are locally created
            // i.e. not received from Help Org via S2S connection
            for (Account newAccount : Trigger.new) {
                if (sharingHelper.isNotReceivedFromHelpOrg(newAccount.ConnectionReceivedId)) {
                    System.debug(LoggingLevel.Info, 'HTAccountTrigger - adding account to be shared - ' + newAccount.Id);
                    accountsToBeShared.add(newAccount);                 
                }
            }
                
        } else if (Trigger.isAfter && Trigger.isUnDelete) {
            // recreate S2S sharing
            accountsToBeShared.addAll(Trigger.new);
    
        }
        
        
        if (Trigger.isBefore && Trigger.isDelete) {
            Boolean disableAccountBeforeDeleteTrigger = HTEnvConfigBean.getInstance().getDisableAccountBeforeDeleteTrigger();
            Boolean disableTrialAccountBeforeDeleteTrigger = HTEnvConfigBean.getInstance().getDisableTrialAccountBeforeDeleteTrigger();
            
            if (!disableAccountBeforeDeleteTrigger) {
                List<HT_Account__c> htAccounts = [Select ID from HT_Account__c where Account__c in :Trigger.old];
                delete htAccounts;
            }

            if (!disableTrialAccountBeforeDeleteTrigger) {
                List<HT_TrialOrg_Account_Link__c> trialAccounts = [Select ID from HT_TrialOrg_Account_Link__c where Account__c in :Trigger.old];
                
                if(trialAccounts.size() > 0)
                    delete trialAccounts;
            }

            
        } else {
            //TODO: patrick/ganesh - revisit the rules for sharing
            // should use the account's orgId
            if(accountsToBeShared.size() > 0 && HTEnvConfigBean.getInstance().isPilotAccountSharingEnabled())
                sharingHelper.createSharingForAccounts(accountsToBeShared);
        }
        
      //This code is for sharing Exact Target accounts to H&T via s2s
        Integer noOfSoqlQueriesAvailable = Limits.getLimitQueries() - Limits.getQueries();
        Integer noOfDMLStatementsAvailable = Limits.getLimitDMLStatements() - Limits.getDMLStatements();
        system.debug('noOfSoqlQueriesAvailable ' +noOfSoqlQueriesAvailable);
        system.debug('noOfDMLStatementsAvailable ' +noOfDMLStatementsAvailable);
        
        //perform a check to make sure we have 4 soql queries  available and 1 DML statement available.
        if(HTEnvConfigBean.getInstance().isAccountSharingEnabled() && !SKIP_ACCOUNT_SHARING_TO_HELP_ORG && noOfSoqlQueriesAvailable >=4 && noOfDMLStatementsAvailable >=1) {
             List<Id> accountIds = new List<Id>();
            if (Trigger.isAfter && (Trigger.isUpdate)) {
                Map<Id,Account> unsharedAccountMap = HTAccountSharingHelper.getUnsharedAccounts(Trigger.newMap);
                if(unsharedAccountMap.size() > 0) {
                	 Set<Id> csps = HTAccountSharingHelper.getSharableCloudServiceProviders();
                     List<Id> notsharedAccountIds = new List<Id>();
                     
                     for(Id accountId: unsharedAccountMap.keySet()) {
                         notsharedAccountIds.add(accountId);
                     }
                     Map<Id,Boolean> accShareMap = HTAccountSharingHelper.getSharableAccountMap(csps,notsharedAccountIds);
                     
                     List<Account> sharableAccounts = new List<Account>();
                     for (Id accountId : unsharedAccountMap.keySet()) {
                         Account notSharedAccount = unsharedAccountMap.get(accountId);
                         if (accShareMap.get(notSharedAccount.Id) != null && accShareMap.get(notSharedAccount.Id) ) {
                             System.debug(LoggingLevel.Info, 'HTAccountTrigger - adding account to be shared - ' + notSharedAccount.Id);
                             sharableAccounts.add(notSharedAccount);
                         }
                     }
                     if(sharableAccounts != null && sharableAccounts.size() > 0) {
                         HTExternalSharingHelper.HTS2SIntegration(sharableAccounts,'Contact,Case',null);
                     }
                } 
            }
                
        }
        
    } catch (System.Exception ex) {
        //Log any errors
        System.debug(LoggingLevel.Error, 'Help Portal HTAccountTrigger failed -' + ex.getMessage());
        errorLog.processException(ex);
    } finally {
        errorLog.logMessage();
    }
}