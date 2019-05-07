trigger eimAccountTrigger on Account bulk (before insert, before update) {
    private static final String ACCOUNT_FIRST_LOGO_SWITCH_ON = 'On';
    private static Boolean checkAccountFirstLogo = (SfdcCMTCompSettings.getInstance().getValue(BaseConstants.CMT_ACCOUNT_FIRST_LOGO_SWITCH) == ACCOUNT_FIRST_LOGO_SWITCH_ON);
    G4GBypassProcess g4gByPass = new G4GBypassProcess();
    
    if((!g4gByPass.isBypassEnabled() ||
        (g4gByPass.isBypassEnabled() && !g4gByPass.isBypassUser()) ||
        !TeamAccountTriggerHandler.isTeamRunning) &&
       checkAccountFirstLogo){
        // Update Accounts and First Logo staging objects
        FirstLogoHandler.setFirstLogo(Trigger.new, Trigger.oldMap);
    }
}