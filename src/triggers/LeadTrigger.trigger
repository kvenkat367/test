/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: sfarrelly $
 * $Change: 12743488 $
 * $DateTime: 2016/12/21 07:35:31 $
 * $File: //it/applications/org62/C2L/patch/Marketing/src/triggers/LeadTrigger.trigger $
 * $Id: //it/applications/org62/C2L/patch/Marketing/src/triggers/LeadTrigger.trigger#27 $
 * $Revision: #27 $
 */
 
trigger LeadTrigger on Lead (before insert, after insert,
                             before update, after update,
                             after delete) {

    private final String NULL_STRING = 'null';

    /* If the current user is one listed in Label.leadBypassUsers, do NOT execute the trigger code.
     * This is intended for high volume DML users (like LEAP API) who make data updates that do not require trigger logic to execute.
     * @author tford  3/19/2010
     */     
    if ( !Org62UserBypass.isLeadBypassUser() ) {


        MarketingResponse mr;
        List<Lead> leadScores = new List<Lead>();
        List<Lead> nonS2sLeads = new List<Lead>(); //Please use this list when writing new process
         Map<Id,id> companyIDs = new Map<Id,Id>();
        LeadTriggerHandler handler = new LeadTriggerHandler(Trigger.oldMap, Trigger.newMap, Trigger.old, Trigger.new);

        if (!Trigger.isDelete){ 
            System.debug('@@@@@ WebToLead ' + Trigger.new[0]);          
            if ( Trigger.new[0].isPRMLead__c && Trigger.new[0].Portal_UserName__c != null && !Trigger.new[0].UserCreationAttempt__c) {
                PP2PartnerUserClass PartnerUser = new PP2PartnerUserClass();
                PartnerUser.CreateLeadPortalUser(Trigger.new[0]);               
                return;
            }


            for (Lead l : Trigger.new){

                if(l.ConnectionReceivedId == null){
                    nonS2sLeads.add(l);
                }
   
                if(l.DandbCompanyId != null) {
                    companyIDs.put(l.DandbCompanyId,l.DandbCompanyId);
                }
            }
        }
        Map<Id, DandBCompany> companyMap =  new Map<Id, DandBCompany>([SELECT Id, dunsnumber FROM DandBCompany WHERE Id IN :companyIDs.keySet()]);
        if( Trigger.isBefore ){
            if( Trigger.isUpdate ){
                handler.handleBeforeUpdate();
            }
            if( Trigger.isInsert ){
                handler.handleBeforeInsert();
            }
        }else if(Trigger.isAfter){
            if( Trigger.isUpdate ){
                handler.handleAfterUpdate();
            }
        }

        // BEFORE Phase
        if (Trigger.isBefore && !LeadConvert.getIsExecutingConvert()) {
                            
           if(LeadAssignmentWorkAround.shouldRunBefore()){ //work-around for bug #189209 remove after 158 mfullmore.
                              
                //Handles Jigsaw leads insert/update
                JigsawIntegrationUtil jigsawLeads = new JigsawIntegrationUtil();
                if (!Trigger.isDelete){
                    for(Lead l : Trigger.new){
                        if(l.RecordTypeId != null){
                            l.Lead_Record_Type_Name__c = l.getActiveRecordTypes().get(l.RecordTypeId);
                        }else {
                            l.Lead_Record_Type_Name__c = NULL_STRING;
                        }
                         if (l.D_U_N_S__c == null && l.DandbCompanyid != null && companyMap != null) {
                            l.D_U_N_S__c = companyMap.get(l.DandbCompanyid).dunsnumber;
                         }
                    }
                    LeadOwnerRoleStamp roleStamp = new LeadOwnerRoleStamp(Trigger.new);
                    
                    if(Boolean.valueOf(Label.mktg_FeatureToggle_EinsteinJobTitleMapping)) {
                        List<Lead> changedBeforeTitle = mktg_LeadsRouter.getInstance().getChangedTitles(Trigger.new, Trigger.oldMap);
                        SyncLeadTitle slt = new SyncLeadTitle(changedBeforeTitle);
                    }else{
                        SyncLeadTitle slt = new SyncLeadTitle(Trigger.new);
                    }
                }
                if(Trigger.isInsert){
                    
                    for(Lead l : Trigger.new){
                        if(l.LeadSource != null){
                            l.Initial_Lead_Source__c = l.LeadSource;
                        }
                        if(l.LeadType__c != null){
                            l.Initial_Offer_Type__c = l.LeadType__c;
                        }
                        if(l.Primary_Product_Interest__c != null){
                            l.Initial_PPI__c = l.Primary_Product_Interest__c;
                        }
                    }

                    // Sync AFT values
                    LeadUtil.syncAFTValuesOnInsert(trigger.new);

                    //send lead marketing response process
                    mr = new MarketingResponse(null, nonS2sLeads);
                    LeadPartnerUserFields.setPartnerUserFields(nonS2sLeads);

                    //sync partner lead
                    SyncPartnerLeadInsert.clearLinkedPartnerLead(Trigger.new);
                    SyncPartnerLeadInsert.changeStatus(nonS2sLeads); 
                    
                    //handles Jigsaw leads insert. For leads with RT = Jigsaw we should stamp the sync field
                    jigsawLeads.stampJigsawLeadsOnInsert(Trigger.new);
                }

                if(Trigger.isUpdate){
                    
                    
                
                    countryCodeMaintenance newMaint = new countryCodeMaintenance();
                    for(Lead lea:Trigger.new) {
                        if(lea.Country != Trigger.oldMap.get(lea.id).Country) {
                            
                            lea = newMaint.fixIsoCodes(lea);
                        }
                    
                    
                    }
                
                    //send lead marketing response process
                    mr = new MarketingResponse(Trigger.old, Trigger.new);

                    //sync partner lead
                    SyncPartnerLeadUpdate splu = new SyncPartnerLeadUpdate();
                    splu.partnerLeadBeforeUpdate(Trigger.new, Trigger.old);  

                    //handles Jigsaw leads update. For leads with RT = Jigsaw we should stamp the sync field
                    jigsawLeads.stampJigsawLeadsOnUpdate(Trigger.new,Trigger.oldMap);

                    

                }
                /*Commented this code because the trigger wasn't triggered on delete, but now is. Probably this was deprecated. ascuccimarra
                if(trigger.isDelete){
                    SyncPartnerLeadDelete spld = new SyncPartnerLeadDelete();
                    spld.partnerLeadBeforeDelete(Trigger.old);
                }*/


            }
            
            if(Trigger.isInsert){
                /* If GDPR is enabled then process leads*/            
                if(Boolean.valueOf(Label.mktg_FeatureToggle_GDPR)) {
                    mktg_LeadsRouter.getInstance().processGDPRConsent(Trigger.new);
                }
                LeadUtil.syncLeadEmailOptOut(Trigger.new);
            }
            
            if(Trigger.isUpdate){
                LeadUtil.syncLeadEmailOptOut(Trigger.new, Trigger.oldMap);
            }
        }

        // AFTER Phase
        if (Trigger.isAfter) {
            if(LeadAssignmentWorkAround.shouldRunAfter()){ //work-around for bug #189209 remove after 158 mfullmore.
                if(Trigger.isInsert){
                    SyncPartnerLeadInsert spli = new SyncPartnerLeadInsert(nonS2sLeads);

                    //fix for bug #661972. grilo.
                    LeadPartnerUserFields.afterInsert(Trigger.new);

                    // Create new Campaign Members
                    LeadUtil.autoCreateCampaignMembers(trigger.new);
                }
                
                if(Trigger.isUpdate){
                    
                    

                   SyncPartnerLeadUpdate splu = new SyncPartnerLeadUpdate();

                   splu.partnerLeadUpdate(Trigger.new);

                    //Convert Child leads, stamp Jigsaw accounts and set the Primary Campaign Source upon lead conversion
                     C2LLeadFutureHandler futureHandler = new C2LLeadFutureHandler();
                     futureHandler.convertLeadAndAccountQualification(Trigger.new, Trigger.oldMap);
                    //If the phone or phone extension are updated, updates the phone extension of related tasks
                    TaskPhoneExtensionUtil tpeu = new TaskPhoneExtensionUtil();
                    tpeu.setTaskPhoneExtensionOnAfterLeadUpdate(Trigger.new,Trigger.oldMap);              

                    LeadAnswersDeleteController.deleteLeadAnswers(Trigger.new, Trigger.oldMap);
                    
                    //Updates contacts M&A field upon lead conversion
                    JigsawIntegrationUtil jigsawUtil = new JigsawIntegrationUtil();
                    jigsawUtil.stampMAFieldOnLeadConversion(Trigger.new, Trigger.oldMap);
                    
                    /* Prevent certain users from selecting "Do not create a new opportunity upon conversion." checkbox
                       when converting leads with specific Record Type or Lead Source values. */
                    LeadUtil.validateUsageOfCheckboxDoNotCreateOpportunity(trigger.new);

                    // Update AFT Values
                    LeadUtil.updateAFTValuesOnLead(trigger.new);

                    // Update AFT on the Contact that came from a converted Lead
                    LeadUtil.updateAFTValuesOnContactFromConvertedLead(trigger.new, trigger.oldMap);
                }
            }
            
            if (Trigger.isDelete) {
                LeadUtil.updateAFTOnMergedLeads(trigger.old);
            }
        }
    }
}