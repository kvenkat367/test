trigger ContactTrigger on Contact (before insert, after insert, before update, after update) {
    
    // @author tford: Skip this code for LeadGen users, to avoid UROG lock in 162.store
    if ( !Org62UserBypass.isBypassLeadGenUser() ) {
        MarketingResponseContact mrc;
        if (Trigger.isBefore) {
            if(Boolean.valueOf(Label.mktg_FeatureToggle_EinsteinJobTitleMapping)) {      
                List<Contact> changedBeforeTitle = mktg_ContactsRouter.getInstance().getChangedTitles(Trigger.new, Trigger.oldMap);
                SyncContactTitle sct = new SyncContactTitle(changedBeforeTitle);
            }else{
                SyncContactTitle sct = new SyncContactTitle(Trigger.new);
            }
            
            ReplaceShippingCountry rsc = new ReplaceShippingCountry(trigger.new);

            if(trigger.isInsert){
                /* If GDPR is enabled then process contacts*/
                if(Boolean.valueOf(Label.mktg_FeatureToggle_GDPR)) {
                    mktg_ContactsRouter.getInstance().processGDPRConsent(Trigger.new);
                }            
                mrc = new MarketingResponseContact(null,trigger.new);
                ContactEmailOptOutUtil.syncContactEmailOptOut(Trigger.new);
            }

            if(trigger.isUpdate){
                mrc = new MarketingResponseContact(trigger.old,trigger.new);
                ContactEmailOptOutUtil.syncContactEmailOptOut(Trigger.new, Trigger.oldMap);               
            }
        }else{
            if (Trigger.isInsert) {
                if (Legal_Denied_Party_Settings__c.getInstance() != null && Legal_Denied_Party_Settings__c.getInstance().Active__c) {
                    //Legal Denied Party verification Process
                    //Set MK Data Service Required flag in  Legal Denied Party Search Object 
                    LegalDeniedParty ldParty = new LegalDeniedParty();
                    ldParty.updateLegalDeniedPartySearch(Trigger.new);
                }
            }
            if(Trigger.isUpdate){
                // Skip phone number update if AppStore/Webstore user (W-872830)
                if(!UserInfo.isAppstoreuser()) {
                    //If the phone or phone extension of the contact are updated, updates the phone with extension fo related tasks
                    TaskPhoneExtensionUtil tpeu = new TaskPhoneExtensionUtil();
                    tpeu.setTaskPhoneExtensionOnAfterContactUpdate(Trigger.new, Trigger.oldMap);
                }
            }
        }

    }
    if( Trigger.isUpdate && Trigger.isAfter ){
       // when contact is moved to different account, recalculate dnm on accounts 
       ContactTriggerHandler cth = new ContactTriggerHandler();
       cth.processAccDNM( Trigger.new, Trigger.oldMap );
    } 
}