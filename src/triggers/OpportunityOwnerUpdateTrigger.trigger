trigger OpportunityOwnerUpdateTrigger on Opportunity bulk(before insert, before update, after update) {
    //if the Q2O Sync is creating Opportunity Lines that results in Opportunity Update, bypass this trigger
    // bypass trigger invocation in case of opportunity update via upsell process
    if(BaseStatus.byPassTriggerLogic('OpportunityOwnerUpdateTrigger')) {
        return;
    }
    OpportunityBatchConfig__c sfSetting = OpportunityBatchConfig__c.getInstance('SpecialistForecastAutoGenProcess');
    if(sfSetting != null){
        if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWith(sfSetting.APIUserName__c)) {
            return;
        }   
    }
    //if opportunity is being updated by the specialist forecast Autogen API user or contract expiration API user, bypass trigger execution.
    if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWithIgnoreCase(sfbase.BaseConstants.CONTRACT_EXPIRATION_API_USER) ){
        return;
    }     

    private  List<Opportunity> opptys  = new List<Opportunity>();
    public   Map<String,String> userRecords = new Map<String,String>();
    public   Map<Id,User> userObj = new Map<Id,User>();
    Map<String,Id> OpptyRecordTypesMap = new Opportunity().getActiveRecordTypesByName();
    Map<Id,String> OpptyRecIdMap = new Map<Id,String>();
    String NEWBIZ_ADDON_RECORD_TYPE_NAME = BaseRecordTypeUtil.OPPTY_RECORD_TYPE_NEWBIZ_ADDON; 
    private Map<Id,SalesProfile__c> opptyUserIdToSPMap = new map<Id,SalesProfile__c>();
    private Map<String,Id> teamRoleMap = new Map<String,Id>();
    public   Map<Id,Id> opptyOwnerMap = new Map<Id,Id>();
    //Defaulted the days to 1.
    public Integer configurableDays = 1;
    //Getting configurable days for salesforceTeam query
    AppConfig ac = new AppConfig();
    private Map<string, AppConfigRecord> allSspSettings = ac.getall('OpptyTeamProcess');
    if(allSspSettings.containsKey('OpptyTeamProcess.OpptyTeamHoldoutDays'))
        configurableDays = Integer.valueof(allSspSettings.get('OpptyTeamProcess.OpptyTeamHoldoutDays').Value);
    
    //teamRoleMap = OpptyTeamUtils.getTeamRoleMap();
    
    for(String rt:OpptyRecordTypesMap.keySet()){
        OpptyRecIdMap.put(OpptyRecordTypesMap.get(rt),rt);
    }
    //BEFORE insert
    if(Trigger.isInsert){
        if(Trigger.isBefore && !LeadConvert.getIsExecutingConvert()){
            Set<String> accIds = new Set<String>();
            Map<string,String> taeOwnerMap = new Map<String,String>();
            for(Opportunity o : Trigger.new){
                accIds.add(o.AccountId);
            }
            sfbase__SalesforceTeam__c[] sfTeamArrData = [ Select id, sfbase__Account__c, sfbase__User__c,
                                                          sfbase__TeamRole__c,sfbase__source__c, Team_Role__c 
                                                          From  sfbase__SalesforceTeam__c
                                                          Where sfbase__Account__c IN : accIds
                                                          And   sfbase__StartDate__c <= : Date.TODAY()
                                                         // And   sfbase__TeamProcessExclude__c = false
                                                          And   sfbase__user__c != null
                                                          And   sfbase__EndDate__c = null
                                                          ];
            for(sfbase__SalesforceTeam__c sfTm : sfTeamArrData){
                if('TAE'.equals(sfTm.sfbase__teamrole__c) && 'Team Selling'.equals(sfTm.sfbase__source__c)){
                    taeOwnerMap.put(sfTm.sfbase__Account__c,sfTm.sfbase__User__c);
                }
                //System.debug('INFO::OpportunityOwnerUpdateTrigger::sfTm role::'+sfTm.sfbase__teamrole__c+' Source::'+sfTm.sfbase__source__c);
            }

            for(Opportunity o : Trigger.new){
                if(BaseRecordTypeUtil.opptyTypesForOpptyTeam.contains(OpptyRecIdMap.get(o.RecordTypeId))){
                    o.sfbase__MarkForOpptyTeamCreate__c = true;
                }
                //System.debug('INFO::OpportunityOwnerUpdateTrigger::taeOwnerMap::'+taeOwnerMap+'AccId::'+o.AccountId);
                if(taeOwnerMap.get(o.AccountId) != null){
                    o.OwnerId = taeOwnerMap.get(o.AccountId);
                }
            }
        }//end of isBefore
    }//end of isInsert

    if(Trigger.isUpdate){
        if(Trigger.isBefore && !LeadConvert.getIsExecutingConvert()) { 
            Set<Id> changedDeals = new Set<Id>();
            Map<Id, sfbase__DealRelationship__c> deals = new Map<Id, sfbase__DealRelationship__c>();
            for(Opportunity oppty : Trigger.new) {
                if(!OrderManagementUtil.IS_QUOTE_CONVERSION_CONTEXT) {
                    SfdcOpportunityHelper.populateChangedDealsForOppty(oppty, Trigger.oldMap.get(oppty.Id), changedDeals);
                }
            }
            if(!changedDeals.isEmpty()) {
                deals = new Map<Id, sfbase__DealRelationship__c>([SELECT sfbase__status__c FROM sfbase__DealRelationship__c WHERE Id IN: changedDeals]);
                for(Opportunity oppty : Trigger.new) {
                    if(oppty.sfbase__DealRelationship__c != Trigger.oldMap.get(oppty.Id).sfbase__DealRelationship__c) {
                        SfdcOpportunityHelper.addErrorOrUpdateDealForOppty(oppty, Trigger.oldMap.get(oppty.Id), deals, UserInfo.getProfileId());
                    }
                }
            }

            Map<Id,boolean> ownerMap = new Map<id,boolean>();
            Map<Id,String> oldOwner = new  Map<Id,String>();
            Map<String,String> opptyTeamsMap = new Map<String,String>();
            Set<Id> uidSet = new Set<Id>();
            sfbase__OpportunityTeam__c[] newOpptyTeamArr = new sfbase__OpportunityTeam__c[0];
            sfbase__OpportunityTeam__c[] newTmpOpptyTeamArr = new sfbase__OpportunityTeam__c[0];
            Map<Id, Decimal> splitMap = new Map<Id, Decimal>();
            Set<Id> opptyCreatedFromLeadIds= new Set<Id>();
            Map<Id, sfbase__OpportunityTeam__c[]> opptyToOpptyTeamsMap = new Map<Id, sfbase__OpportunityTeam__c[]>();
            sfbase__OpportunityTeam__c[] opptyTeamArrayOfOppty = new sfbase__OpportunityTeam__c[0];
            set<Id> accountIds = new Set<Id>();      
            Map<Id, sfbase__SalesforceTeam__c[]> accIdToSFTeamMap = new Map<Id, sfbase__SalesforceTeam__c[]>();     

            for(Opportunity o : Trigger.New){
                Opportunity old = System.Trigger.oldMap.get(o.id);
                if(o.ownerid != old.ownerid){
                    o.sfbase__MarkForOpptyTeamCreate__c = true;
                    ownerMap.put(o.id,true);
                    uidSet.add(o.ownerid);
                    oldOwner.put(o.id,old.ownerid);
                    opptyOwnerMap.put(o.id,o.ownerid);
                    accountIds.add(o.accountId);
                }
                

                //if the record type has changed 
                if(old.RecordTypeId != o.RecordTypeId){
                    //and if the old RecorType IS NOT one of the values from the custom setting, and the new RecordType IS 
                    //one of the values from the custom setting 
                    if(!BaseRecordTypeUtil.opptyTypesForOpptyTeam.contains(OpptyRecIdMap.get(old.RecordTypeId)) &&
                         BaseRecordTypeUtil.opptyTypesForOpptyTeam.contains(OpptyRecIdMap.get(o.RecordTypeId))){
                        //then set the MarkforOpptyTeamCreate__c as true
                        o.sfbase__MarkForOpptyTeamCreate__c = true;
                    }
                } 
                                
                //get the list of all oppties created from lead conversion.  We need to check if opptyTeam exists for these
                //Added to the lead specific opptyIds only if this oppty is converted from lead and if 
                //the user is not explicitly changing this flag MarkForOpptyTeamCreate__c  
                if(o.sfbase__MarkForOpptyTeamCreate__c !=true && o.Converted_Lead_Record_Type_Name__c != null &&
                    old.sfbase__MarkForOpptyTeamCreate__c == o.sfbase__MarkForOpptyTeamCreate__c){
                    //System.debug('INFO::OpportunityOwnerUpdateTrigger::This oppty is converted from lead ' + o.id); 
                    opptyCreatedFromLeadIds.add(o.id);
                }                
                if(!BaseRecordTypeUtil.opptyTypesForOpptyTeam.contains(OpptyRecIdMap.get(o.RecordTypeId)))
                    o.sfbase__MarkForOpptyTeamCreate__c = false;               
               
            }
            //System.debug('INFO::OpportunityOwnerUpdateTrigger::ownerMap::'+ownerMap+' uidSet::'+uidSet+' oldOwner::'+oldOwner);
            
            //check if oppty team exists and check MarkForOpptyTeamCreate flag if needed for the oppty created from lead.
            if(opptyCreatedFromLeadIds.size() > 0){                
                for(sfbase__opportunityTeam__c[] opptyTeamsArrayData :[Select id,sfbase__User__c, sfbase__SplitPercent__c,sfbase__Division__c,
                                                             sfbase__EndDate__c,sfbase__MarketSegment__c,sfbase__CompValidationRole__c,
                                                             sfbase__Opportunity__c, sfbase__OpptyOwner__c, sfbase__Source__c
                                                             from sfbase__opportunityTeam__c
                                                             where sfbase__opportunity__c IN :opptyCreatedFromLeadIds
                                                             and sfbase__enddate__c = null] ){                                                             
                                                             
                    for(sfbase__opportunityTeam__c opptyTeam : opptyTeamsArrayData ){
                        //construct the Map with Oppty to OpptyTeam
                        //try to get the OpptyTeam from the Map by passing the oppty as key
                        //if it doesn't exist, create the new array from the opptyTeam member and add to the Map
                        //if it exists then, append the opptyTeam member to the array.
                        if(opptyToOpptyTeamsMap.get(opptyTeam.sfbase__opportunity__c) != null){
                            opptyTeamArrayOfOppty = opptyToOpptyTeamsMap.get(opptyTeam.sfbase__opportunity__c);
                            opptyTeamArrayOfOppty.add(opptyTeam);
                        }else{
                            opptyTeamArrayOfOppty = new sfbase__OpportunityTeam__c[0];
                            opptyTeamArrayOfOppty.add(opptyTeam);
                        }
                        opptyToOpptyTeamsMap.put(opptyTeam.sfbase__Opportunity__c, opptyTeamArrayOfOppty);
                                       
                    }
                }
                for(Opportunity o : Trigger.New){  
                    //get the opptyTeam for the oppty from the Map
                    //System.debug('INFO::OpportunityOwnerUpdateTrigger::Oppty to OpptyTeams map ' + opptyToOpptyTeamsMap); 

                    sfbase__OpportunityTeam__c[] fetchedOpptyTeam = opptyToOpptyTeamsMap.get(o.id);
                    if(!(fetchedOpptyTeam != null && fetchedOpptyTeam.size()> 0) && 
                            BaseRecordTypeUtil.opptyTypesForOpptyTeam.contains(OpptyRecIdMap.get(o.RecordTypeId)) &&
                            opptyCreatedFromLeadIds.contains(o.Id)){
                        o.sfbase__MarkForOpptyTeamCreate__c = true;
                    }
                }                  
            }//end block            
            
            if(oldOwner != null && oldOwner.size() > 0){
            
            //Getting the team roles only for owner change..
            teamRoleMap = OpptyTeamUtils.getTeamRoleMap();
            
                for(sfbase__opportunityTeam__c[] opptyTeamsArr :[Select id,sfbase__User__c, sfbase__SplitPercent__c,sfbase__Division__c,
                                                             sfbase__EndDate__c,sfbase__MarketSegment__c,sfbase__CompValidationRole__c,
                                                             sfbase__Opportunity__c, sfbase__OpptyOwner__c, sfbase__Source__c, sfbase__Validated__c,Territory__c
                                                             from sfbase__opportunityTeam__c
                                                             where sfbase__opportunity__c IN :oldOwner.keySet()
                                                             // and sfbase__User__c IN :oldOwner.values()
                                                             and sfbase__enddate__c = null]){
                    for(sfbase__opportunityTeam__c opptyTeam : opptyTeamsArr){
                        opptyTeamsMap.put(opptyTeam.sfbase__opportunity__c+''+opptyTeam.sfbase__User__c, opptyTeam.id);
                        if(opptyTeam.sfbase__OpptyOwner__c == false) {
                            newTmpOpptyTeamArr.add(opptyTeam);
                        }
                    }
                }
                //Get the user data from User's object for the owner of Opportunity
                userRecords  = OpptyTeamUtils.getUsersData(uidSet);
                userObj      = OpptyTeamUtils.getUsersObjects();
                //Getting sales profile for opptyowner 
                opptyUserIdToSPMap = OpptyTeamUtils.getSalesProfile(opptyOwnerMap.Values());
                accIdToSFTeamMap = getSalesforceTeamMap(accountIds);

                for(Opportunity o : Trigger.New){

                    sfbase__SalesforceTeam__c st = new sfbase__SalesforceTeam__c();

                    //If the owner is changed then only add a new row to Opportunity Team
                    if(ownerMap.get(o.id) != null){
                        sfbase__OpportunityTeam__c newOpptyTeamRow = new sfbase__OpportunityTeam__c();
                        if(userRecords != null){
                            newOpptyTeamRow.sfbase__CompOwnerRole__c =  userRecords.get(o.ownerid);
                        }
                        
                        //fetching Oppty owner's salesforeTeam record
                        if(accIdToSFTeamMap.containsKey(o.accountId) && accIdToSFTeamMap.get(o.accountId) != null){
                            for(sfbase__SalesforceTeam__c sfTeam : accIdToSFTeamMap.get(o.accountId)){
                                if(o.ownerId == sfTeam.sfbase__user__c){
                                st = sfTeam;
                                }
                            }
                        }

                        newOpptyTeamRow.sfbase__Opportunity__c = o.Id;
                        if(userObj.get(o.ownerid) == null) {
                            newOpptyTeamRow.sfbase__CompValidationRole__c = '';
                            newOpptyTeamRow.sfbase__Division__c = '';
                            newOpptyTeamRow.sfbase__MarketSegment__c = '';
                            newOpptyTeamRow.sfbase__SplitPercent__c = null;
                        } else {
                            newOpptyTeamRow.sfbase__CompValidationRole__c = OpptyTeamUtils.getCompRateData(userObj.get(o.ownerid).sfbase__Market_Segment__c);
                            newOpptyTeamRow.sfbase__Division__c = userObj.get(o.ownerid).sfbase__corporateDivision__c;
                            newOpptyTeamRow.sfbase__MarketSegment__c = userObj.get(o.ownerid).sfbase__Market_Segment__c;
                            newOpptyTeamRow.sfbase__SplitPercent__c = OpptyTeamUtils.getOpptyOwnerDefaultACV(OpptyTeamUtils.getCompRateData(userObj.get(o.ownerId).sfbase__Market_Segment__c));
                        }

                        newOpptyTeamRow.sfbase__EligibleForRenewalComp__c = o.Account.sfbase__EligibleForRenewalComp__c;
                        newOpptyTeamRow.sfbase__StartDate__c = System.Today();
                        newOpptyTeamRow.sfbase__Source__c = OpptyTeamUtils.SOURCE_PROCESS;
                        newOpptyTeamRow.sfbase__TeamQuota__c = o.Account.sfbase__TeamQuota__c;
                        newOpptyTeamRow.sfbase__opptyowner__c = true;
                        newOpptyTeamRow.sfbase__User__c = o.ownerId;
                        newOpptyTeamRow.sfbase__LevelOfAccess__c = 'Read/Write';
                        //newOpptyTeamRow.sfbase__TeamRole__c  = 'Opportunity Owner';

                        //Checking for TeamRole lookup of owner record in sfTeam ,if not looking into salesprofile records , if no records in salesprofile making Teamrole as Salesperson
                        if(st != null && st.Team_Role__c!=null){
                            newOpptyTeamRow.TeamRoleLookup__c = st.Team_Role__c;
                        }else if(opptyUserIdToSPMap != null && 
                            opptyOwnerMap != null && 
                            opptyOwnerMap.containsKey(o.id) && 
                            opptyOwnerMap.get(o.id) != null && 
                            opptyUserIdToSPMap.containsKey(opptyOwnerMap.get(o.id))){
                            
                            newOpptyTeamRow.TeamRoleLookup__c = OpptyTeamUtils.getTeamRoleForOwnerRecord(opptyUserIdToSPMap,opptyOwnerMap.get(o.id),teamRoleMap);    
                        }
                        newOpptyTeamRow.Territory__c = OpptyTeamUtils.getSFTeamTerritoryId(st);
                     
                        newOpptyTeamArr.add(newOpptyTeamRow);
                        newTmpOpptyTeamArr.add(newOpptyTeamRow);

                        //System.debug('INFO::oldId::'+opptyTeamsMap.get(o.id+''+oldOwner.get(o.Id)));

                        if(opptyTeamsMap.get(o.id+oldOwner.get(o.Id)) != null){
                            newOpptyTeamRow = new sfbase__OpportunityTeam__c(id = opptyTeamsMap.get(o.id+''+oldOwner.get(o.Id)));
                            newOpptyTeamRow.sfbase__endDate__c = System.today();
                            TextUtil.writeDebug('1) Inactivating oppty team: ' + newOpptyTeamRow.Id);
                            newOpptyTeamArr.add(newOpptyTeamRow);
                        }

                        if(opptyTeamsMap.containsKey(o.id+''+o.ownerId)){
                            newOpptyTeamRow = new  sfbase__OpportunityTeam__c(id =opptyTeamsMap.get(o.id+''+o.ownerId));
                            newOpptyTeamRow.sfbase__endDate__c = System.today();
                            TextUtil.writeDebug('2) Inactivating oppty team: ' + newOpptyTeamRow.Id);
                            newOpptyTeamArr.add(newOpptyTeamRow);
                        }
                        //System.debug('newOpptyTeamArr$$$'+newOpptyTeamArr);
                    }
                    splitMap  = OpptyTeamUtils.calculateSplitBaseMap(newTmpOpptyTeamArr);
                    if(splitMap.size() > 0){
                        o.sfbase__AE__c = splitmap.get(o.id);               
                    }
                }

                try{
                    if(newOpptyTeamArr != null || newOpptyTeamArr.size() > 0) {
                        Textutil.writeDebug('newOpptyTeamArr.size() = ' + newOpptyTeamArr.size());
                        upsert newOpptyTeamArr;
                    }
                }catch(DMLException ex){
                    // Remove the errored rows
                    Integer i;
                    for (i = ex.getNumDml() - 1; i>=0; i--) {
                        // Remove errored out rows
                        newOpptyTeamArr.remove(ex.getDmlIndex(i));
                    }
                    if (newOpptyTeamArr.size() > 0) {
                        // try again to upsert good rows
                        upsert newOpptyTeamArr;
                    }
                }
            }
            for(Opportunity o : Trigger.new) {
                if(o.RecordTypeId == OpptyRecordTypesMap.get(NEWBIZ_ADDON_RECORD_TYPE_NAME)
                    ||  o.RecordTypeId == opptyRecordTypesMap.get(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_MC_NEWBIZ)  
                    && (o.sfquote__Quote_Exists__c)){
                    //if split base percentage is greater than or equal to 100, do not add split adjustment sku and update the message on the Oppty Header Error messages field   
                    if(o.sfbase__AE__c != null && o.sfbase__AE__c >= 100){            
                        if(o.sfbase__OpptyTeamErrorMsg__c !=null && o.sfbase__OpptyTeamErrorMsg__c != '' ){
                            if(!o.sfbase__OpptyTeamErrorMsg__c.contains(Label.splitBaseHundredOrMore)){
                                o.sfbase__OpptyTeamErrorMsg__c += '\n' + Label.splitBaseHundredOrMore; 
                            }
                        }else{
                            o.sfbase__OpptyTeamErrorMsg__c = Label.splitBaseHundredOrMore;
                        }
                    }else{ //if split base is a valid value then remove the error message
                        if(o.sfbase__OpptyTeamErrorMsg__c !=null && o.sfbase__OpptyTeamErrorMsg__c!= ''){
                            o.sfbase__OpptyTeamErrorMsg__c = o.sfbase__OpptyTeamErrorMsg__c.remove(Label.splitBaseHundredOrMore);
                        }
                    }
                }
            }
            //When there is split base specified, adjust the OTV and ACT amounts on the Opportunity
            //split logic
            SfdcOpptyTriggerHelper.splitOpptyOTVAndACVAmounts(Trigger.New,Trigger.oldMap);      
            //end of split logic    
        } else { // Trigger.isAfter
             // Logic to create an entry on custom Oppty Team Process Account queue - unchecking is handled by bulk Oppty Team Process
            Set<Id> teamAccIds = new Set<Id>();
            List<Opportunity> oppList = new List<Opportunity>();
            List<OpptyTeamProcessAccount__c> opptyTeamAccs = new List<OpptyTeamProcessAccount__c>();
            for(Opportunity op: Trigger.New){
                if(op.sfbase__MarkForOpptyTeamCreate__c == true && op.AccountId != null){
                    teamAccIds.add(op.AccountId);
                }
            }
            
            if(!teamAccIds.isEmpty()){
                for(Id accid:teamAccIds ){
                    opptyTeamAccs.add(new OpptyTeamProcessAccount__c(AccountId__c = accid,  processForOpptyTeam__c = TRUE));
                }
                Schema.SObjectField ex_id = OpptyTeamProcessAccount__c.Fields.AccountId__c;
                Database.Upsert(opptyTeamAccs,ex_id,false); 
            }           
            // end Oppty Team Process Account reference flag
            
            if(SfdcOpportunityHelper.getUpdatedDealsForOppty().size() > 0) {
                List<String[]> gacks = new List<String[]>();
                try {
                    update SfdcOpportunityHelper.getUpdatedDealsForOppty().values();
                } catch(System.DmlException dex) {
                    Integer i;
                    for(i = dex.getNumDml() - 1; i >= 0; i--) {
                        // Get errored out deal id
                        sfbase__DealRelationship__c badDeal = SfdcOpportunityHelper.getUpdatedDealsForOppty().get(dex.getDmlId(i));
                        // Add to bad deal id set with message for display/api
                        gacks.add(new String[] {'Error when updating Opportunity for Deal Relationship ' + badDeal.Id, dex.getDmlMessage(i)});
                        // Remove any problematic deals from the updated list
                        SfdcOpportunityHelper.getUpdatedDealsForOppty().remove(dex.getDmlId(i));
                    }
                    if(!SfdcOpportunityHelper.getUpdatedDealsForOppty().isEmpty()) {
                        // Try again to update with good ones
                        update SfdcOpportunityHelper.getUpdatedDealsForOppty().values();
                    }
                    SfdcOpportunityHelper.processGacks(gacks);
                } catch(Exception ex){
                    gacks.add(new String[] {'Error when updating Opportunity for Deal Relationship ', ex.getMessage()});
                    SfdcOpportunityHelper.processGacks(gacks);
                }
            }            
            Map<Id, String> oppts = new Map<Id, String>();
            for(Opportunity o : Trigger.New) {
                if(o.StageName != null 
                    && o.StageName.contains('Closed') 
                        && o.StageName != Trigger.oldMap.get(o.Id).StageName
                        && (o.RecordTypeId == OpptyRecordTypesMap.get(TextUtil.NEWBIZ_ADDON_RECORD_TYPE_NAME)
                             || o.RecordTypeId == OpptyRecordTypesMap.get(TextUtil.NEWBIZ_ADDON_LOCKED_RECORD_TYPE_NAME)
                             || o.RecordTypeId == opptyRecordTypesMap.get(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_MC_NEWBIZ)
                             || o.RecordTypeId == opptyRecordTypesMap.get(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_MC_NEWBIZ_LOCKED)) ){
                            
                        TextUtil.writeDebug('oppts' + oppts + ', o.StageName = ' + o.StageName + ', o.Name = ' + o.Name + ' and o.RecordTypeId = ' + o.RecordTypeId);
                        oppts.put(o.Id, o.Name);
                    }
                    
                // Code to send an email to oppty owner and Pam on Oppty Team if Partner Comments field is updated
                if(o.Partner_Comments__c != Trigger.oldMap.get(o.Id).Partner_Comments__c){
                    oppList.add(o);
                }
            }
            if(oppts != null && oppts.size() > 0) {
                sfbase__opportunityTeam__c[] opptyTeamsArr = [Select id,sfbase__User__c,sfbase__User__r.email,sfbase__User__r.name, sfbase__SplitPercent__c,sfbase__Division__c,
                                                              sfbase__EndDate__c,sfbase__MarketSegment__c,sfbase__CompValidationRole__c,
                                                              sfbase__Opportunity__c, sfbase__OpptyOwner__c, sfbase__Validated__c
                                                              from sfbase__opportunityTeam__c
                                                              where sfbase__opportunity__c IN : oppts.keySet()
                                                              and sfbase__enddate__c = null];                       
                TextUtil.writeDebug('opptyTeamsArr:: '+opptyTeamsArr);
                OpptyTeamUtils.sendSplitPercentEmail(opptyTeamsArr, oppts);
            }
            if(oppList!=null && oppList.size()>0)
                SfdcProposalUtil.sendEmailPAMandOpptyOwner(oppList);

            //Chatter Post For Auto Genrated Add On Oppty
            ChatterPostForAutoGenAddOnOppty.postToChatter(Trigger.oldMap, Trigger.newMap ,OpptyRecordTypesMap);
        }//end of isAfter
    }//end of isUpdate

    private Map<Id,sfbase__SalesforceTeam__c[]> getSalesforceTeamMap(Set<Id> accIds){
        Map<Id, sfbase__SalesforceTeam__c[]> accIdToSFTeamMap = new Map<Id, sfbase__SalesforceTeam__c[]>();
        sfbase__SalesforceTeam__c[] sfTeamArrayData = new sfbase__SalesforceTeam__c[]{};
        sfbase__SalesforceTeam__c[] sfTeamArr = new sfbase__SalesforceTeam__c[]{};

        try{
            sfTeamArrayData = [ Select id, sfbase__Account__c, sfbase__User__c,
                                                          sfbase__TeamRole__c,sfbase__source__c, Team_Role__c,Territory__c 
                                                          From  sfbase__SalesforceTeam__c
                                                          Where sfbase__Account__c IN : accIds
                                                          And   sfbase__StartDate__c <= : Date.TODAY()
                                                         // And   sfbase__TeamProcessExclude__c = false
                                                          And   sfbase__user__c != null
                                                          And   sfbase__EndDate__c = null
                                                          ];

            //Creating map for salesforce team for each account with key accountId
            for(sfbase__SalesforceTeam__c sfTeamCntr : sfTeamArrayData){ 
                
                if(accIdToSFTeamMap.get(sfTeamCntr.sfbase__Account__c) != null){
                        sfTeamArr = accIdToSFTeamMap.get(sfTeamCntr.sfbase__Account__c);
                        sfTeamArr.add(sfTeamCntr);
                }else{
                        sfTeamArr = new sfbase__SalesforceTeam__c[]{};
                        sfTeamArr.add(sfTeamCntr);
                }                    
                        accIdToSFTeamMap.put(sfTeamCntr.sfbase__Account__c, sfTeamArr);
            }  
        }catch(Exception e){
            system.debug('Exception Details::'+e.getmessage());
        }
        return accIdToSFTeamMap;
    }
}