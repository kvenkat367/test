/*
* RelEng Perforce/RCS Header - Do not remove!
*
* $Author: rajesh.retnaswamy $
* $Change: 14906331 $
* $DateTime: 2017/11/27 15:39:16 $
* $File: //it/applications/org62/Shared/patch/Shared/src/triggers/AccountTrigger.trigger $
* $Id: //it/applications/org62/Shared/patch/Shared/src/triggers/AccountTrigger.trigger#37 $
* $Revision: #37 $
*/
/*
* types of bypass processes and flags used
* - G4GBypassProcess
* - Org62FireTriggerCheck.trafficLightUtilIsRecursive
* - Org62UserBypass.runAccountTrigger()
* - Org62UserBypass.isBypassLeadGenUser()
* - G4GAlignmentTeamBypassProcess
* - TeamAccountTriggerHandler.isYearlyRealignment
* different teams who have code here
* - adm-it
* - solar-it
* - services & support - it
* - legal & agreements - it
* - partner portal
*/
trigger AccountTrigger on Account ( before insert, after insert, before update, after update,
                                                        before delete, after delete, after undelete ){
    
    /*
    * @author: solar-it
    * - this is to skip acc trigger modules when skipAccountTriggers is set to true
    *   from solar code base
    */
    if( BaseStatus.skipAccountTriggers ){
        // exit the trigger
        return;
    }
    /*
    * @author: adm-it
    * Initialization of trigger manager for junk process
    * required for junking (after update) and un-junking (before update)
    * - have static flag based controls to make sure this block is called only once
    * - should be called as first thing in update event
    */
    AccountADMTriggerManager accADMTriggerManager;
    if( Trigger.isUpdate ){
        accADMTriggerManager = new AccountADMTriggerManager( Trigger.new,Trigger.old,
                                                             Trigger.newmap,Trigger.oldMap );
        if( Trigger.isBefore){
            /*
            * @author: adm-it
            * Used to check Do Not Merge flag to True for winning record
            */
            accADMTriggerManager.updateDoNotMerge();
        }
    }
    /*
    * @author: adm-it
    * link account to company process during before insert/update
    */
    if( Trigger.isBefore 
        && 
        ( 
            ( Trigger.isInsert && !LeadConvert.getIsExecutingConvert() ) 
            || 
            ( Trigger.isUpdate )
        ) 
    ){
        // initialize constructor for linking account to company
        AccountADMTriggerManager accADMTrigManager = new AccountADMTriggerManager( Trigger.new,Trigger.newmap,
                                                        Trigger.oldMap, Trigger.isUpdate );
        // call method to link account to company
        accADMTrigManager.processLinkAccToCmp();
    }
    
    // @author: p2c-it
    // If it is before insert or before update operation, then 
    // call the method which checks the Account fields and set the First Logo Eligible field
    if(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)){
        FirstLogoHandler.setFirstLogo(Trigger.new, Trigger.oldMap);
    }
    
    // @author: adm-it
    // check for team bypass 
    // - if team engine is already running or
    // - if current user is team bypass user
    if( AccountADMTriggerManager.checkForTeamBypass() ){  
        /*
        * @author: adm-it
        * - process of populating sic and related field values on account
        */
        accADMTriggerManager = new AccountADMTriggerManager( Trigger.new,Trigger.old,
                                                             Trigger.newmap,Trigger.oldMap );
        // before insert, before update
        if ( Trigger.isBefore && !Trigger.isDelete 
                && !Org62FireTriggerCheck.trafficLightUtilIsRecursive ){            
            // process of populating sic and related field values on account
            accADMTriggerManager.sicLookupProcess();
        }
    }
    // if team engine is not running or 
    // if the current user is not team bypass user
    else{
        /*
        * @author: adm-it
        * Used to ensure un-junked accounts are processed first
        * so team engine will run properly on them
        */
        if( Trigger.isBefore && Trigger.isUpdate){
            accADMTriggerManager.updateUnJunkedAccount();
        }        
        /* 
        * @author: alexis.williams@salesforce.com / services & support team
        * Used to process accounts for Project Accelerate
        */
        if( Trigger.isUpdate && Trigger.isBefore){
            // initializing the AccountADMTriggerManager handler class 
            // - by calling the constructor with trigger context values for before update
            accADMTriggerManager = new AccountADMTriggerManager( null, Trigger.newMap, null, null, null ); 
            // calling trigger manger class helper method to to set account graduated status
            accADMTriggerManager.accAccelerateProcess();
        }
        /*
        * @author: adm-it
        * data.com enrichment post processing
        */ 
        if( Trigger.isUpdate && Trigger.isBefore){
            accADMTriggerManager = new AccountADMTriggerManager( Trigger.new,Trigger.old,
                                                             Trigger.newmap,Trigger.oldMap );
            accADMTriggerManager.ddcEnrichProcess();
        }
        // checks different custom label based bypass process
        // @author: adm-it
        if( Org62UserBypass.runAccountTrigger() ){            
            // sft, rules of engagement related functionality behind account merge
            // works for losing records only
            /* 
            * @author: adm-it
            * account merge process
            */
            if ( Trigger.isDelete ){
                accADMTriggerManager = new AccountADMTriggerManager( Trigger.old, Trigger.oldMap );                                         
                // tbd
                if( Trigger.isBefore){
                    accADMTriggerManager.processBeforeMerge();
                }
                // tbd
                if( Trigger.isAfter ){
                    accADMTriggerManager.valDoNotMerge();
                }
            }
            /* 
            * @author: solar-it
            * @author tford
            * Skip this code initially for Accounts created by LeadGen users, to avoid UROG lock in 162.store
            * Accomplished through the Account.Defer_MyPatch__c flag.
            * Defer_MyPatch__c is set to true by default on an Account, it is later set to false by time-based workflow.
            * MyPatch will assign the appropriate owner at that point.
            */ 
            // initializing for lead gen bypass process           
            Account[] newAccounts;
            Account[] oldAccounts;
            Map<Id, Account> newAccMap;
            Map<Id, Account> oldAccMap;
            // if lead gen user bypass
            if ( Org62UserBypass.isBypassLeadGenUser() ){
                newAccounts = new Account[]{};
                oldAccounts = new Account[]{};
                for ( Integer accountPos = 0; accountPos < Trigger.new.size() ; accountPos++ ){
                    // If the Defer MyPatch flag is false, add this account to the list to be processed
                    if ( Trigger.new[accountPos].Defer_MyPatch__c == false ){
                        newAccounts.add( Trigger.new[accountPos] );
                        newAccMap.put( Trigger.new[accountPos].Id, Trigger.new[accountPos] );
                        // If there are Accounts in Trigger.old, remove the corresponding entry
                        if( Trigger.isUpdate ){
                            oldAccounts.add( Trigger.old[accountPos] );
                            oldAccMap.put( Trigger.old[accountPos].Id, Trigger.old[accountPos] );
                        }
                    }
                }
            }
            // if not lead gen user bypass, collect the new and old list as it is
            else{
                // If current user isn't a LeadGen user, process the full data
                newAccounts = Trigger.new;
                oldAccounts = Trigger.old;
                newAccMap = Trigger.newMap;
                oldAccMap = Trigger.oldMap;
            }
            /*
            * @author: adm-it
            * <If there are no Accounts to process as LeadGen user, don't try>
            * if its not a lead gen user OR it is a lead gen user and new list has records
            */ 
            if( 
                ( 
                    ( !Org62UserBypass.isBypassLeadGenUser() )
                    || 
                    ( !newAccounts.isEmpty() )
                )
                &&
                ( !Org62FireTriggerCheck.trafficLightUtilIsRecursive )
            ){
                // if its trigger before insert 
                if( Trigger.isBefore 
                    && 
                    Trigger.isInsert 
                    && 
                    !LeadConvert.getIsExecutingConvert() ){
                    /*
                    * @author: adm - it
                    */
                    // initializing the AccountADMTriggerManager handler class 
                    // - by calling the constructor with trigger context values for before update
                    accADMTriggerManager = new AccountADMTriggerManager( Trigger.new, null, null, false, true );
                    // establish sic related field values for accounts collected
                    // - happening second time
                    accADMTriggerManager.sicLookupProcess(); 
                    // calling trigger manger class helper method to sync acc product pitch status
                    accADMTriggerManager.processAccProductPitchStatusSync();
                }
                // if its trigger before update
                else if( Trigger.isBefore && Trigger.isUpdate ){
                    /*
                    * @author: adm - it
                    */
                    // initializing the AccountADMTriggerManager handler class 
                    // - by calling the constructor with trigger context values for before update
                    accADMTriggerManager = new AccountADMTriggerManager( Trigger.new, null, Trigger.old, true, false ); 
                    // establish sic related field values for accounts collected
                    // - happening second time
                    accADMTriggerManager.sicLookupProcess();
                    // calling trigger manger class helper method to sync acc product pitch status
                    accADMTriggerManager.processAccProductPitchStatusSync();
                    /*
                    * @author: p2c
                    * - Legal Denied Party process
                    */
                    // initializing the AccountADMTriggerManager handler class 
                    // - by calling the constructor with trigger context values for before update
                    accADMTriggerManager = new AccountADMTriggerManager( Trigger.new, null, Trigger.old, true, false ); 
                    // calling trigger manger class helper method to 
                    // update legal denied party search object with account info 
                    accADMTriggerManager.legalDeniedPartyProcess();
                }
                // if its trigger after insert 
                else if( Trigger.isAfter && Trigger.isInsert ){ 
                    /*
                    * @author: partner portal team
                    */
                    // initializing the AccountADMTriggerManager handler class 
                    // - by calling the constructor with trigger context values for before update
                    accADMTriggerManager = new AccountADMTriggerManager( newAccounts, null, null, false, true ); 
                    // calling trigger manager class helper method to process named account for gsi during acc insert
                    accADMTriggerManager.processPP2GSINamedAccount();
                    /*
                    * @author: adm-it
                    * team engine process
                    */
                    //
                    if( !newAccounts.isEmpty() ){
                        // get the bypass settings for g4g alignment
                        G4GAlignmentTeamBypassProcess byPassUserRequest = new G4GAlignmentTeamBypassProcess();
                        // if bypass is not enabled or (bypass enabled and bypass user exist )
                        if( 
                            ( !byPassUserRequest.isBypassEnabled() ) 
                            || 
                            ( byPassUserRequest.isBypassEnabled() && byPassUserRequest.isUserExists() ) 
                          ){
                            /*
                            * @author: adm-it
                            * TEAM engine process after create - will not be called twice because of 
                            * flag in TeamAccountTriggerHandler
                            */
                            TeamAccountTriggerHandler teamAccountHandler 
                                                      = new TeamAccountTriggerHandler( newAccounts, oldAccounts, newAccMap,
                                                                                                   null, false, false );                    
                            teamAccountHandler.onAfterInsert();
                        }
                    }
                    /*
                    * @author: p2c
                    * - Legal Denied Party process
                    */ 
                    // initializing the AccountADMTriggerManager handler class 
                    // - by calling the constructor with trigger context values for after insert
                    accADMTriggerManager = new AccountADMTriggerManager( Trigger.new, null, null, false, true ); 
                    // calling trigger manger class helper method to 
                    // update legal denied party search object with account info 
                    accADMTriggerManager.legalDeniedPartyProcess();                      
                }
                // if its trigger after update
                else if( Trigger.isAfter &&Trigger.isUpdate ){
                    /*
                    * @author: adm-it
                    * team engine process
                    */
                    // instantiate/load bypass flag
                    G4GAlignmentTeamBypassProcess byPassUserRequest = new G4GAlignmentTeamBypassProcess();
                    // check if the bypass process is not enabled or ( bypass is enabled and user is bypass user )
                    if( 
                        ( !byPassUserRequest.isBypassEnabled() ) 
                        || 
                        ( byPassUserRequest.isBypassEnabled() && byPassUserRequest.isUserExists() ) 
                      ){
                        // instantiate for TEAM engine processing
                        TeamAccountTriggerHandler teamAccountHandler 
                                                =  new TeamAccountTriggerHandler( newAccounts, oldAccounts, newAccMap, 
                                                                                               oldAccMap, false, true );
                        // TEAM engine processing
                        teamAccountHandler.onAfterUpdate();
                    }
                    /*
                    * @author: adm-it
                    */
                    // initializing the AccountADMTriggerManager handler class 
                    // - by calling the constructor with trigger context values for before update
                    accADMTriggerManager = new AccountADMTriggerManager( newAccounts, null, oldAccounts, true, false ); 
                    // calling trigger manger class helper method to sync acc member owner
                    accADMTriggerManager.processAccMemberOwnerSync();
                    /*
                    * @author: partner portal
                    */   
                    // initializing the AccountADMTriggerManager handler class 
                    // - by calling the constructor with trigger context values for before update
                    accADMTriggerManager = new AccountADMTriggerManager( newAccounts, null, oldAccounts, true, false ); 
                    // calling trigger manager class helper method to process named account for gsi during acc update              
                    accADMTriggerManager.processPP2GSINamedAccount();  
                }
            }
        }// end of Org62UserBypass.runAccountTrigger()
        /*
        * @author: solar-it
        */
        if( Trigger.isAfter && Trigger.isUpdate ){
            // calling trigger manger class helper method to 
            // update legal denied party search object with account info 
            // accADMTriggerManager.processOpptyUpsellUpdate();
        }
    }// end of else part of g4gbypass process OR team running process
    /*
    * @author: adm-it
    * junking process after account update
    * - should be called after every other process
    */
    if( Trigger.isAfter && Trigger.isUpdate ){
        accADMTriggerManager = new AccountADMTriggerManager( Trigger.new,Trigger.old,
                                                             Trigger.newmap,Trigger.oldMap );
        accADMTriggerManager.updateJunkToArchive();
    }
    /*
    * @author: adm-it
    * enrichment source capture on before update and after insert
    */
    if( Trigger.isBefore && Trigger.isUpdate ){
        // initializing the AccountADMTriggerManager handler class 
        // - by calling the constructor with trigger context values for before update
        accADMTriggerManager = new AccountADMTriggerManager( Trigger.new, Trigger.newMap,
                                                             Trigger.oldMap, true );  
        // calling this method to capture the enrichment sources                                                          
        accADMTriggerManager.upsertEnrichmentSource();
    }
    else if( Trigger.isAfter && Trigger.isInsert ){
        // initializing the AccountADMTriggerManager handler class 
        // - by calling the constructor with trigger context values for after insert
        accADMTriggerManager = new AccountADMTriggerManager( Trigger.new, Trigger.newMap, 
                                                             null, false );  
        // calling this method to capture the enrichment sources                                                          
        accADMTriggerManager.upsertEnrichmentSource();
    }
}