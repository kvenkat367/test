/**
 * Trigger owned by PartnerPortal Team to sync the partner accounts information 
 * with the TZ org
 * @author Copyright (c) 2014 Salesforce.com.
 * @author kvyas@salesforce.com
 *
 */
trigger PartnerAccountTrigger on Account (after insert, after update) {
    
    // creating object for TeamBypassHelper class to bypass team engine    
    TeamBypassHelper teamByPass = new TeamBypassHelper();
    // check for team bypass recursive call
    // - if team bypass check is already executed,then it will be false
    if( !TeamBypassHelper.TEAM_BYPASS_CHECK_DONE ){
        // admConfigManager custom setting process field name
        String TEAM_BYPASS_SETTING = 'TeamBypassSetting';
        // setting static flag to true to avoid recursive calls for team bypass
        TeamBypassHelper.TEAM_BYPASS_CHECK_DONE = true;
        // calling helper class method to validate current logged in user
        // - if current user is team bypass user,then it will return true else false and 
        //   storing it in a static variable to use during recursive calls
        TeamBypassHelper.IS_TEAM_BYPASS_USER = teamByPass.isTeamBypassUser( TEAM_BYPASS_SETTING );
        // team engine bypass check
        // - skipping other modules when g4g or other integration jobs
        //   executes team engine
        if( TeamBypassHelper.IS_TEAM_BYPASS_USER ){
            return;
        }
    }
    // if its recursive team bypass check
    else{
        // check for the static variable which is set to true/false
        // during the first time of team bypass execution
        if( TeamBypassHelper.IS_TEAM_BYPASS_USER ){
            return;
        }
    }
    //
    List<String> partnerAccountIds = new List<String>();
    RecordType partnerAccountRecordType = [SELECT Id, Name FROM RecordType WHERE sObjectType = 'Account' And name = 'Partner' ];
    System.debug('UserInfo profile --' + userInfo.getUserId());
        
    PermissionSetAssignment[] apiOnlyUserPermAssinged = [SELECT Id, PermissionSet.PermissionsApiUserOnly FROM PermissionSetAssignment where AssigneeId =: UserInfo.getUserId() and  PermissionSet.PermissionsApiUserOnly = true ];
    
    System.debug('apiOnlyUserPermAssinged --' + apiOnlyUserPermAssinged);
    
    /* call SyncApi if not API only user to avoid 
     *  callout loop exception.
     */     
    if(apiOnlyUserPermAssinged.isEmpty() && !System.isFuture()) {
    
        for(Account pAccount : trigger.new) {
        
            if(pAccount.RecordTypeId == partnerAccountRecordType.Id) {            
                partnerAccountIds.add(pAccount.Id);
            }
        }
        // future callout to sync information
        if(!partnerAccountIds.isEmpty()){
            PP2PartnerAccountSyncAPI.syncPartnerAccountsInTZ(partnerAccountIds);    
        }
    }
    
}