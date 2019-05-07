trigger HT62OpportunityMigration on Opportunity (before insert, after insert, before update, after update, after delete) {
    Set<String> bypassUserIds = HTEnvConfigBean.getInstance().getAccountTriggerByPassUserIds();
    if(bypassUserIds.contains(UserInfo.getUserId())) {
        return;
    }
    String RecordTypeId = HTEnvConfigBean.getInstance().getOpportunityEducationRecordTypeId();
    List<Opportunity> validOpptys = new List<Opportunity>();
    Set<String> optyDeOrgIds = new Set<String>();
    Org62ErrorHandlingUtil errorLog = Org62ErrorHandlingUtil.getInstance();
    Boolean isHTIREnabled = HTIR_Utils.isHTIREnabled(HTIR_Constants.SOBJECT_TYPE_ROSTER, HTIR_Constants.ORG62DE_CONNECTION_NAME);
    Boolean ConnectionUser = (!isHTIREnabled && HTOrg62Integration.CheckConnectionUser()) || (HTIR_Utils.isConnectionUser(UserInfo.getUserId()) && isHTIREnabled);
    if(Trigger.isAfter && Trigger.isDelete){
        Set<String> rosterIdSet = new Set<String>();
        if (!ConnectionUser && isHTIREnabled && !HTOrg62Integration.isRosterOpptyDelRecursion){
            HTOrg62Integration.isRosterOpptyDelRecursion = true;
            for(Opportunity Opp_Item:Trigger.old){
                if( RecordTypeId == Opp_Item.get('RecordTypeId') && String.isNotBlank(Opp_Item.DE_Org_ID__c) ){
                    rosterIdSet.add(Opp_Item.DE_Org_ID__c);
                }
            }
            if(!rosterIdSet.isEmpty()){
                List<Roster__c> rosterList = [SELECT Id FROM Roster__c Where Opportunity_ID__c IN:rosterIdSet];
                if(rosterList != null && rosterList.size() >0){
                   try{
                        delete rosterList;
                    }
                    catch (System.Exception ex) {
                           errorLog.processException(ex);
                    } finally {
                           errorLog.logMessage();
                    }
                }
            }
        }
    }else{
        //populate valid opptys in a set
        for (Opportunity opportunity : trigger.new) {
             if (RecordTypeId != null && RecordTypeId != opportunity.get('RecordTypeId')){
                continue;
            }
            validOpptys.add(opportunity);
        }
        if(!validOpptys.isEmpty()){
            if (trigger.isBefore && trigger.isInsert) {
                //Continue only if batch contains valid opptys
                if(validOpptys.size() > 0){
                    for(Opportunity opp:  validOpptys){
                        // Avoid blank values
                        if (String.isNotBlank(opp.DE_Org_ID__c)) {
                            optyDeOrgIds.add(opp.DE_Org_ID__c);
                        }
                    }
                    // The purpose of this query seems to be to avoid creating an Opportunity with a duplicate DE_Org_ID__c
                    // Asumming that currently there are no repeated DE Org Ids (a safe assumption if our code works ok)
                    // Worst Case scenario, as much there will be one repeated DE Org ID for each of the Opportunities being processed by each trigger batch (which is always 200 per documentation)
                    Opportunity[] LOpp = [SELECT DE_Org_ID__c FROM Opportunity WHERE RecordTypeId = :RecordTypeId AND DE_Org_ID__c IN :optyDeOrgIds];
                    Map<String, Id> LMap = new Map<String, Id>();
                    for (Opportunity Opp_Item : LOpp) {
                       LMap.put(Opp_Item.DE_Org_ID__c, Opp_Item.Id);
                    }
                    for (Opportunity Opp_item : trigger.new) {
                        if (LMap.get(Opp_item.DE_Org_ID__c)!=null) {
                            // This means that there's an Oppty on the database with the same DE_Org_ID__c that the Oppty we're trying to insert
                            // So we put it to null and give a new timestamp below
                            Opp_item.DE_Org_ID__c = null;
                        }
                        if (Opp_item.DE_Org_ID__c == null) Opp_item.DE_Org_ID__c = 'O'+system.now().format('DyyHHmmssS')+string.valueof(math.random()).replace('.','');
                    }
                    if (!ConnectionUser) {
                        if (RecordTypeId != null) {
                            Set<Id> CampaignClass = new Set<Id>();
                            for (Opportunity OppItem : trigger.new) {
                               LA_OpportunityMigrationHelper.setClassDiscountFields(OppItem);
                               CampaignClass.add(OppItem.Education_Event__c);
                            }
                            Map<Id,Campaign> CheckClass = new Map<Id,Campaign>([select id,LMS_Last_Integration_Message__c FROM Campaign WHERE Id in: CampaignClass]);
                            for (Opportunity OppItem : trigger.new) {
                                if (RecordTypeId!=null && RecordTypeId != OppItem.get('RecordTypeId')) continue;
                                if (OppItem.CloseDate == null) {
                                    OppItem.CloseDate = OppItem.Education_Event__r.EndDate;
                                }
                                Campaign temp_Campaign = CheckClass.get(OppItem.Education_Event__c);
                                String classStr;
                                if (temp_Campaign != null) {
                                    
                                    classStr = temp_Campaign.LMS_Last_Integration_Message__c;
                                }
                                ID class_Id = null;
                                try {
                                    if (String.isBlank(classStr)) {
                                        OppItem.DE_Org_ID__c = null;
                                    }
                                    class_Id = classStr;
                                } catch (Exception E) {
                                    OppItem.DE_Org_ID__c = null;
                                }
                            }
                        }
                        HTOrg62Integration.SyncContact(trigger.new);
                    }
                }
            } else if (trigger.isBefore && trigger.isUpdate) {
                for (Opportunity oppItem : validOpptys) {
                    if (oppItem.DE_Org_ID__c == null || (oppItem.DE_Org_ID__c != null && oppItem.DE_Org_ID__c.trim().length() == 0)) {
                        oppItem.DE_Org_ID__c = 'O'+system.now().format('DyyHHmmssS')+string.valueof(math.random()).replace('.','');
                    }
                    //automatically update fields for employees on stage change
                    if(HTUserHelper.isEmployee(oppItem.AccountId) && Trigger.oldMap.get(oppItem.Id).StageName != null && Trigger.oldMap.get(oppItem.Id).StageName.equals('08 - Waitlisted')){
                        if(oppItem.StageName.equals('03 - Registered')){
                            oppItem.LeadSource = 'Web/Marketing';
                            oppItem.PromotionCode__c = 'EMPLOYEE';
                            oppItem.Next_Steps__c = 'Registration complete';
                            oppItem.Payment_Type__c = 'N/A';
                        }else if(oppItem.StageName.equals('12 - Cancelled - Employee')){
                            oppItem.LeadSource = 'Web/Marketing';
                            oppItem.Reason_Cancelled__c = 'Not Approved';
                        }
                    }
                    if (!ConnectionUser) {
                        LA_OpportunityMigrationHelper.setClassDiscountFields(oppItem); 
                        if (Trigger.newMap.get(oppItem.Id).StageName != Trigger.oldMap.get(oppItem.Id).StageName) {
                            if (oppItem.StageName == '03 - Registered') {
                                oppItem.CloseDate = Date.Today();
                            }
                        }
                    }

                }
                //Continue only if batch contains valid opptys
                if (!ConnectionUser && validOpptys.size() >0) {
                    
                    HTOrg62Integration.SyncContact(validOpptys);
                }
            } else {
                system.debug('NAME ====='+UserInfo.getName()+' === TYPE '+ UserInfo.getUserType());
                Boolean syncException = false;
                if (!ConnectionUser) {
                    try {
                        HTOrg62Integration.RosterSync(trigger.isUpdate, validOpptys);
                        
                    } catch (Exception E){
                        syncException = true;
                        String ErrorMsg = 'The system has encountered the following error while saving the data: <exception>. Please contact your system administrator.';
                        ErrorMsg = ErrorMsg.replace('<exception>',E.getMessage());
                        
                        for (Opportunity Opp_Item : trigger.new) {
                            
                            //Opp_Item.adderror(Label.ht_invalide_training_event_for_opportunity);
                            Opp_Item.adderror(ErrorMsg);
                        }
                    }
                }
                //Continue only if batch contains valid opptys
                if(!syncException){
                    HTOrg62Integration.sendCancellationEmails(validOpptys, Trigger.oldMap, Trigger.isUpdate, RecordTypeId);
                }
            }

            if(trigger.isAfter && trigger.isUpdate && !HTOrg62Integration.CheckConnectionUser()) {
                List<Opportunity> newOpps = [SELECT Id, StageName, LastModifiedById, Education_Event__r.Enrollment_Maximum__c, Education_Event__r.Attendee_Total__c FROM Opportunity WHERE Id in :Trigger.newMap.keySet()];
                for (Opportunity newOpp : newOpps) {
                    Opportunity oldOpp = Trigger.oldMap.get(newOpp.Id);
                    if(newOpp.StageName.equals('03 - Registered') && !oldOpp.StageName.equals('03 - Registered') && newOpp.Education_Event__r.Attendee_Total__c >= newOpp.Education_Event__r.Enrollment_Maximum__c) {
                        ConnectApi.FeedItemInput feedItemInput = new ConnectApi.FeedItemInput();
                        
                        ConnectApi.MessageBodyInput messageBodyInput = new ConnectApi.MessageBodyInput();
                        
                        ConnectApi.MentionSegmentInput mentionSegmentInput = new ConnectApi.MentionSegmentInput();
                        ConnectApi.TextSegmentInput textSegmentInput = new ConnectApi.TextSegmentInput();
                        
                        messageBodyInput.messageSegments = new List<ConnectApi.MessageSegmentInput>();
                        
                        mentionSegmentInput.id = newOpp.LastModifiedById;
                        messageBodyInput.messageSegments.add(mentionSegmentInput);
                        
                        textSegmentInput.text = ' Registration may overenroll the class.';
                        messageBodyInput.messageSegments.add(textSegmentInput);
                        
                        feedItemInput.body = messageBodyInput;
                        feedItemInput.feedElementType = ConnectApi.FeedElementType.FeedItem;
                        feedItemInput.subjectId = newOpp.Id;
                        
                        ConnectApi.FeedElement feedElement = ConnectApi.ChatterFeeds.postFeedElement(Network.getNetworkId(), feedItemInput, null);
                    }
                }
            }
        }
    }
}