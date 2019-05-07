trigger OpportunityTrigger on Opportunity (before insert, after insert,
                                           before update, after update,
                                           after delete,
                                           after undelete) {

    //if the Q2O Sync is creating Opportunity Lines that results in Opportunity Update, bypass this trigger        
    // bypass trigger invocation in case of opportunity update via upsell process                                  
    if(BaseStatus.Q2OSyncLineCreationRunning || BaseStatus.copyACVRunning || BaseStatus.isOppUpsellRunning) {
        return;
    } 
    OpportunityTriggerSettings__c settings = OpportunityTriggerSettings__c.getInstance();
    
    List<skip62OrgOpptyTrigger__c> skipusers = skip62OrgOpptyTrigger__c.getall().values();
    Boolean skipUser = false;
    
    for(skip62OrgOpptyTrigger__c Userstoskiprec : skipusers) {
        if(Userinfo.getUsername().contains(Userstoskiprec.Name))
           skipUser = true;    

        if(BaseStatus.batchQuoteCreationRunning == true)
            skipUser = true;
    }

    private BigDealAlert bda;
    private List<Opportunity> nonS2sOpptys = new List<Opportunity>();
    private DreamforceOppty dfopptys = new DreamforceOppty();

    if(!Trigger.isDelete){
        for(Opportunity o : Trigger.new){
            if(o.ConnectionReceivedId == null && o.Type != BaseConstants.OPPTY_TYPE_RENEWALS_UPLIFT){
                nonS2sOpptys.add(o);
            }
        }
    }

    // BEFORE Phase
    if ( Trigger.isBefore ) {

        //Effectively disable Lead conversion into existing Opportunity                                           
        if(!LeadConvertHandler.isLeadConversionToOpptyAllowed(
                LeadConvert.getIsExecutingConvert(),
                Trigger.isInsert,
                Trigger.isUpdate)){

                for(Opportunity o : Trigger.New){
                    o.addError(LeadConvertHandler.errorMessage);   
                }
        } 

        if(!LeadConvert.getIsExecutingConvert()){
             
        
        SaProcess saProcess = new SaProcess(nonS2sOpptys);
        OpportunitySalespersonProcess osp = new OpportunitySalespersonProcess(nonS2sOpptys);

        // Before Update
        if ( Trigger.isUpdate ) {

            // Synchronization code for the Dreamforce registration app
            if (settings != null && settings.DreamforceEnabled__c) {
                dfopptys.DreamforceOpptyUpdate(Trigger.old, Trigger.new);
            }
            
            OpportunityStageChange.assignHasStageChanged(Trigger.old, Trigger.new);
            bda = new BigDealAlert(nonS2sOpptys);

            //Sync Owner_Manager__c with Owner.sf62user__manager__c
            OpptyOwnerManagerSyncOnOppty ownerManagerSync = new OpptyOwnerManagerSyncOnOppty(Trigger.new, Trigger.old);

            OpportunityManagementUtilitiesClass.OpptyFireCount++;

            //For SE Utility Process 
            SEUtilityOpportunityTriggerHandler.updateSEUtilityFlag(Trigger.New, Trigger.oldMap);
            
            // before update trigger condition - added as part of contact role validations
            // since it's only front end validation, checking for the trigger.new list size to avoid firing it in case bulk updates
            if(Trigger.New.size() == 1 && !SalesEnhancementsUtil.isOppInsert){
                // get the opp ids with satisfying criteria
                Map<Id,Opportunity> oppMapSet = SalesEnhancementsUtil.getOppForContactRoleValidation(Trigger.New);
                Set<Id> oppIdOfContactRoleSet = new Set<Id>();
                set<Id> oppIdRenewalContactRoleSet = new Set<Id>();
                if(oppMapSet != null && !oppMapSet.isEmpty()){
                    // get opportunity contact role records for the opportunity
                    for(OpportunityContactRole opp : [Select Id, OpportunityId,Role from OpportunityContactRole where OpportunityId IN : oppMapSet.keyset()]){

                        if(OppMapset.get(Opp.opportunityId).RecordTypeId == SalesEnhancementsUtil.newBizRecTypeId){
                            oppIdOfContactRoleSet.add(opp.OpportunityId);
                        }
                        else if(SalesEnhancementsUtil.RenewalsIDList.contains(OppMapset.get(Opp.opportunityId).RecordTypeId) && opp.Role == 'Renewal Contact'){
                            oppIdRenewalContactRoleSet.add(opp.opportunityId);
                        }
                    }      
                    for(opportunity oppRec : oppMapSet.values()){
                        // in case opportunity does not have opp contact role record throw an error           
                        if(!oppIdOfContactRoleSet.contains(oppRec.Id) && oppRec.RecordTypeId == SalesEnhancementsUtil.newBizRecTypeId){
                            Trigger.newMap.get(oppRec.Id).addError('A Minimum of one Contact Role is required on this Opportunity');
                        }
                        if(SalesEnhancementsUtil.RenewalsIDList.contains(OppRec.RecordTypeId) && !oppIdRenewalContactRoleSet.contains(OppRec.id) ){
                            trigger.newMap.get(oppRec.Id).addError(System.Label.ContactRolesRenewalsErrorMessage);

                        }
                    }
                }
            }

            //PCS field update validation. Raise error message when oppty record type and user profile is not eligible to update PCS field
            OpptyPCSTriggerHandler.opptyPCSValidation(Trigger.newMap, Trigger.oldMap);
        }

        // Before Insert
        if ( Trigger.isInsert ) {

            // Synchronization code for the Dreamforce registration app
            if (settings != null && settings.DreamforceEnabled__c) {
                dfopptys.DreamforceOpptyInsert(Trigger.new);
            }

            BigDealAlert.clearSentEmail(nonS2sOpptys);
            bda = new BigDealAlert(nonS2sOpptys);
            OpportunityClone.cloneOpptys(nonS2sOpptys);

            for(Opportunity o : Trigger.new){
                if(o.LeadSource != null){
                    o.Initial_Lead_Source__c = o.LeadSource;
                }
                if(o.Lead_Type__c != null){
                    o.Initial_Offer_Type__c = o.Lead_Type__c;
                }
                if(o.Primary_Product_Interest__c != null){
                    o.Initial_PPI__c = o.Primary_Product_Interest__c;
                }
            }

            //Create Oppty Roles
            OpptyCreateRoles opptyRoles = new OpptyCreateRoles(Trigger.new);
            
            //Sync Owner_Manager__c with Owner.sf62user__manager__c
            OpptyOwnerManagerSyncOnOppty ownerManagerSync = new OpptyOwnerManagerSyncOnOppty(Trigger.new, null);

            //For SE Utility Process 
            SEUtilityOpportunityTriggerHandler.updateSEUtilityFlag(Trigger.New, Trigger.oldMap);
        }
        }
    }
    // AFTER Phase
    if(Trigger.isAfter){
        OpportunityManagementUtilitiesClass utils = new OpportunityManagementUtilitiesClass();

        // After Insert
        if ( Trigger.isInsert ) {
            
            // set all Opportunities that were created as part of lead conversion.
            if(LeadConvert.getIsExecutingConvert()){
                LeadConversionTriggersHelper.convertedOpptyIds.addAll(Trigger.newMap.keySet());
            }

            // flag value will be checked as part of update for contact role phase 2 validation
            SalesEnhancementsUtil.isOppInsert = true;
            OpptyAddPartnerToSalesteam.addPartner(Trigger.new);

            // Synchronization code for the Dreamforce registration app
            if (settings != null && settings.DreamforceEnabled__c) {
                dfopptys.DreamforceOpptyContactRoleInsertion(null, Trigger.new);
            }

            // LMS insert process
            LMSOpptyUpdateCampaignRevenue.updateCampaign(null, nonS2sOpptys);

            // Call Whitespace Status Sync if not Order Summary API user
            if (!Org62UserBypass.isBypassOrderSummaryAPIUser()) {
                WhitespaceStatusSync.sync(Trigger.new, null);
            }

            //portal 2.0 code
            //W-2530054 : The below condition is added to skip the partner portal code for specific users. Please look into custom settings "skip62OrgOpptyTrigger__c" for list of users.
            if(!skipUser){
               utils.createSalesTeam(nonS2sOpptys, true);

               PP2GSINamedAccountUtility.processOpptiesInsert(Trigger.new);
            }

             //Legal Denied Party verification Process
            //Set MK Data Service Required flag in  Legal Denied Party Search Object
            if (Legal_Denied_Party_Settings__c.getInstance() != null && Legal_Denied_Party_Settings__c.getInstance().Active__c) {
                LegalDeniedParty ldParty = new LegalDeniedParty();
                ldParty.updateLegalDeniedPartySearch(Trigger.new);
            }

            // Set Last Touch Protection AE and/or SR on associated Account
            //LastTouchAccountOpptyTracking lt = new LastTouchAccountOpptyTracking(null, Trigger.new);

            //call pcs re assignment logic
            OpptyPCSTriggerHandler.reassignPCSOnAfterInsert(Trigger.newMap); 

        }
        // After Update
        else if ( Trigger.isUpdate ) {
            //CopyOpptyProductACVFields.copyACVFieldsOnUpdate(Trigger.oldMap,Trigger.newMap);  // Commented by SCH after moving to SFDCOpportunityTrigger
            LMSOpptyUpdateCampaignRevenue.updateCampaign(Trigger.old, Trigger.new);

            // Synchronization code for the Dreamforce registration app
            if (settings != null && settings.DreamforceEnabled__c) {
                dfopptys.DreamforceOpptyContactRoleInsertion(Trigger.old, Trigger.new);
            }

            if ( OpportunityManagementUtilitiesClass.OpptyFireCount == 1 ) {
                OpportunityProjectUtil.createProjectsFor(Trigger.old, Trigger.new);
            }

            // Call Whitespace Status Sync if not Order Summary API user
            if (!Org62UserBypass.isBypassOrderSummaryAPIUser()) {
                if ( !Org62FireTriggerCheck.opptyFireWhitespace ) {
                    WhitespaceStatusSync.sync(Trigger.new, Trigger.old);
                }
            }
            
            //portal 2.0 code
            //W-2530054 : The below condition is added to skip the partner portal code for specific users. Please look into custom settings "skip62OrgOpptyTrigger__c" for list of users.
            if(!skipUser){
               utils.updateSalesTeam(Trigger.old, Trigger.new);
               OpportunityManagementUtilitiesClass.OpptyFireCount++;

               PP2GSINamedAccountUtility.processOpptiesUpdate(Trigger.old, Trigger.new);
            }   
            //spotProfileUtil spu = new spotProfileUtil();
            //spu.doOppties(Trigger.new);

            // Set Last Touch Protection AE and/or SR on associated Account
            //LastTouchAccountOpptyTracking lt = new LastTouchAccountOpptyTracking(Trigger.old, Trigger.new);    

          /*  if(PSEMCustomSettingsHandler.get().getIsSettingDefined() && PSEMCustomSettingsHandler.get().getIsOpptyTriggerActive() != null &&
                PSEMCustomSettingsHandler.get().getIsOpptyTriggerActive()){

                PSEMOpptyUtil psemOpptyCls = new PSEMOpptyUtil(trigger.new, trigger.oldMap);
                psemOpptyCls.createChatterPost();
                psemOpptyCls.psemAutoFollow();
            }*/

        }
        // After Undelete
        else if ( Trigger.isUndelete ) {
            LMSOpptyUpdateCampaignRevenue.updateCampaign(null, nonS2sOpptys);
        }
        // After Delete
        else if ( Trigger.isDelete ) {
            LMSOpptyUpdateCampaignRevenue.updateCampaign(null, Trigger.old);

            // Call Whitespace Status Sync if not Order Summary API user
            if (!Org62UserBypass.isBypassOrderSummaryAPIUser()) {
                WhitespaceStatusSync.sync(Trigger.old, null);
            }
        }
    }
}