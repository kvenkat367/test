/**
 * @author rsubramani, auzzaman
 * @since store.162
 *
 */
trigger RenewalOpportunityTrigger on Opportunity bulk(before update, after update) {
    public static final String DATA_QUALITY_CATEGORY = 'RenewalsDataQuality';
    public static final String FORECAST_ATTRITION_NAME = 'Renewal Forecast Attrition';
    public static final String PROFILE_NAME = 'RM Profiles';
    public static final String PRICEBOOK_NAMES = 'Pricebook Names';
    public static final String RENEWAL_UPLIFT_SYNC_FEATURE_FLAG = 'RenewalUpliftSync.Enable Uplift Oppty Sync';

    //if the Q2O Sync is creating Opportunity Lines that results in Opportunity Update, bypass this trigger (Q2OSyncLineCreationRunning)
    // bypass trigger invocation in case of opportunity update via upsell process OR 
    // Bypass trigger for lead conversion, as leads convert into oppty of NewBusiness - AddON RT
    if(BaseStatus.byPassTriggerLogic('RenewalOpportunityTrigger') || LeadConvert.getIsExecutingConvert()) {
       return;
    }
    
    //if opportunity is being updated by the specialist forecast user, bypass trigger execution.
    if(UserInfo.getUserName() != null && (UserInfo.getUserName().startsWithIgnoreCase(sfbase.BaseConstants.SPECIALIST_FORECAST_API_USER) || UserInfo.getUserName().startsWithIgnoreCase('it-partnerportal@salesforce.com')) ){
        return;
    }     

    Id opptyLockRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_RENEWAL_ATTRITION_LOCKED);
    Id mcOpptyLockRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_MC_NEWBIZ_RENEWAL_ATTRITION_LOCKED);
    Id opptyRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_RENEWAL_ATTRITION);        
    Id mcOpptyRTId = RenewalOpptyUtil.getOpptyRTIdByName(BaseRecordTypeUtil.OPPTY_RECORD_TYPE_MC_NEWBIZ_RENEWAL_ATTRITION);
    Id conSalesRTId = RenewalOpptyUtil.getContractRTIdByName(BaseRecordTypeUtil.CONTRACT_RECORD_TYPE_SALES);
    Id conSrvsRTId = RenewalOpptyUtil.getContractRTIdByName(BaseRecordTypeUtil.CONTRACT_RECORD_TYPE_SERVICES);
    Id conJPRTId = RenewalOpptyUtil.getContractRTIdByName(BaseRecordTypeUtil.CONTRACT_RECORD_TYPE_JP_LICENSE);
    
    String userLogin = UserInfo.getUserName();
    String userProfileId = UserInfo.getProfileId();

    // get the custom setting values for data quality feature for creating the task to Rm when there is no red account
    Map<String,String> configDataValues = SalesConfigurationsManager.getSalesConfigurationsByCategory(DATA_QUALITY_CATEGORY);
    Map<Id,Opportunity> conOpptyMapDataQuality = new Map<Id,Opportunity>();

    Set<String> pricebookNameSet = new Set<String>();
    Set<String> profileIdsSet = new Set<String>();

    if(configDataValues != null && configDataValues.size() > 0 &&
        configDataValues.containsKey(PRICEBOOK_NAMES) && configDataValues.get(PRICEBOOK_NAMES) != null){
        for(String s : configDataValues.get(PRICEBOOK_NAMES).split(';')){
            pricebookNameSet.add(s + '%');
        }
    }

    if(configDataValues != null && configDataValues.size() > 0 &&
        configDataValues.containsKey(PROFILE_NAME) && configDataValues.get(PROFILE_NAME) != null){
        profileIdsSet.addAll(configDataValues.get(PROFILE_NAME).split(';'));
    }

    if(Trigger.isUpdate && Trigger.isBefore && !BaseStatus.autoRenewalProcessRunning && !userLogin.startsWith(eimUtils.RENEWAL_USER_NAME)) {
        Map<Id,Id> opptyMap=new Map <Id,Id>();
        Map<Id,Opportunity> ctrsToUpdate =new Map<Id,Opportunity>();
        Map<Id,OpportunityContract__c[]> opptyCtrsMap = new Map<Id,OpportunityContract__c[]>();
        Set<Id> opptyIds = new Set<Id>();
        Map<Id,Opportunity> opptyIdsACV = new Map<Id,Opportunity>();
        Set<Id> allRenewalOpptyIds = new Set<Id>();
        
        for(Opportunity oppty : Trigger.new) {
            
            if(oppty.sfbase__PriorContractPrimary__c != (Trigger.oldMap.get(oppty.Id).sfbase__PriorContractPrimary__c) && (oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId == mcOpptyRTId)){
                opptyMap.put(oppty.Id,oppty.sfbase__PriorContractPrimary__c);
            }
            //If a quote existed previously for this oppty, then the opso values would not have been overriden
            //Hence when the quote no longer exists override only for those corresponding opptys
            if((!oppty.sfquote__Quote_Exists__c && System.trigger.oldMap.get(oppty.Id).sfquote__Quote_Exists__c) && (oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId == mcOpptyRTId)) {
                opptyIds.add(oppty.Id);
            }
            if((oppty.sfbase__Audited_Prior_ACV_value__c !=oppty.sfbase__PriorAnnualContractValue__c && oppty.sfbase__Audited_Prior_ACV_value__c != System.trigger.oldMap.get(oppty.Id).sfbase__Audited_Prior_ACV_value__c) && (oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId == mcOpptyRTId) ) {
                opptyIdsACV.put(oppty.Id, oppty);
            }
            if((!oppty.sfquote__Quote_Exists__c) && (oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId == mcOpptyRTId || oppty.RecordTypeId == opptyLockRTId || oppty.RecordTypeId == mcOpptyLockRTId)) {
                allRenewalOpptyIds.add(oppty.Id);
            }
        }

        if(!userLogin.startsWith('ordersummary_api@salesforce.com') && !opptyIdsACV.isEmpty()) {
            RenewalOpptyUtil renOpptyUtil = new RenewalOpptyUtil();
            renOpptyUtil.upsertUnAllocOPSO(opptyIdsACV);
        }

        if(!userLogin.startsWith('ordersummary_api@salesforce.com') && !opptyIds.isEmpty()) {
            sfbase__OpportunityProductSummary__c[] opsos = [SELECT Id, sfbase__Opportunity__c,  sfbase__Opportunity__r.License_At_Risk_Reason__c, sfbase__Opportunity__r.ACV_Reason_Detail__c, sfbase__PriorMonthlyOrderValue__c, sfbase__RMOverride__c, sfbase__DefaultRenewalQuantity__c, sfbase__PriorQuantity__c, sfbase__OTVCriteria__c,  sfbase__ForecastedOTV__c, sfbase__PriorOTV__c, sfbase__ForecastedPureOTV__c, sfbase__PriorPureOTV__c, ReasonForLoss__c, ReasonForLossDetail__c 
                                                            FROM sfbase__OpportunityProductSummary__c
                                                            WHERE sfbase__Opportunity__c IN: opptyIds and sfbase__ProductFamily__c !='Unallocated'];
            if(opsos != null && !opsos.isEmpty()) {
                List<sfbase__OpportunityProductSummary__c> updatedOpsos = new List<sfbase__OpportunityProductSummary__c>();
                for(sfbase__OpportunityProductSummary__c opso : opsos) {
                    //If RM Override is checked, then we still have to retain the current opso values
                    if(!opso.sfbase__RMOverride__c) {
                        opso.sfbase__ForecastedRenewalQuantity__c = opso.sfbase__DefaultRenewalQuantity__c;
                        //Reducing the precision because when saved the precision of all the fields are 2. So making it 8 didnt really serve any purpose during recreate
                        if(opso.sfbase__PriorQuantity__c != null && opso.sfbase__PriorQuantity__c != 0 && opso.sfbase__ForecastedRenewalQuantity__c != null && opso.sfbase__ForecastedRenewalQuantity__c != 0 && opso.sfbase__PriorMonthlyOrderValue__c != null) {
                            opso.sfbase__ForecastedMonthlyOrderValue__c = opso.sfbase__PriorMonthlyOrderValue__c * (((Decimal)opso.sfbase__ForecastedRenewalQuantity__c).divide((Decimal)opso.sfbase__PriorQuantity__c, 2, RoundingMode.HALF_EVEN));
                            if(opso.sfbase__PriorOTV__c != null){
                                opso.sfbase__ForecastedOTV__c = opso.sfbase__PriorOTV__c * (((Decimal)opso.sfbase__ForecastedRenewalQuantity__c).divide((Decimal)opso.sfbase__PriorQuantity__c, 2, RoundingMode.HALF_EVEN));
                            }
                            //update forecasted pure OTV only in the case when it is purely OTV family and not a Hybrid family, in other words, PriorOTV is the same as the PriorPureOTV
                            if(opso.sfbase__PriorPureOTV__c != null && opso.sfbase__PriorOTV__c != null &&  opso.sfbase__PriorOTV__c == opso.sfbase__PriorPureOTV__c){
                                opso.sfbase__ForecastedPureOTV__c = opso.sfbase__PriorPureOTV__c * (((Decimal)opso.sfbase__ForecastedRenewalQuantity__c).divide((Decimal)opso.sfbase__PriorQuantity__c, 2, RoundingMode.HALF_EVEN));
                            }                           
                        } else {
                            opso.sfbase__ForecastedMonthlyOrderValue__c = 0.0;
                            opso.sfbase__ForecastedOTV__c = 0.0;
                            opso.sfbase__ForecastedPureOTV__c = 0.0;
                        }
                        updatedOpsos.add(opso);
                    }
                }
                RenewalOpptyUtil.setUpdatedOpsos(updatedOpsos);
            }
        }
        
        //call the util method to fetch the OTV data for Renewal Opportunities
        Map<Id, RenewalOpptyUtil.RenewalOTVOppty> renewalOpptyOTVMap = new Map<Id, RenewalOpptyUtil.RenewalOTVOppty>();
        if(!allRenewalOpptyIds.isEmpty()){
             renewalOpptyOTVMap = RenewalOpptyUtil.getOpptyOTVAmountsMap(allRenewalOpptyIds);
        }
        //Added map to capture the OpportunityContract__c records count related to the opportunity. 
        //to remove the ContractAssociationCount__c field reference.
        Map<Id, Integer> countOfRecordsMap = new Map<Id, Integer> ();
        if(System.Trigger.new != null && System.Trigger.new.size()>0)
        {            
            for(OpportunityContract__c rec : [select id,OpportunityId__c from OpportunityContract__c where OpportunityId__c in : System.Trigger.new ])
            {
                if(countOfRecordsMap.containsKey(rec.OpportunityId__c))
                {
                    Integer count = countOfRecordsMap.get(rec.OpportunityId__c);
                    count = count+1;
                    countOfRecordsMap.put(rec.OpportunityId__c,count);
                }
                else
                {
                    Integer count=1;
                    countOfRecordsMap.put(rec.OpportunityId__c,count);
                }               
            }
        }
        //For Renewal Opportunities, If quote doesn't exist, set oppty amt OTV amount(OTV__C+ACV__C) or the annualized value based on if it meets the OTV Criteria
        //if quote doesn't exit
        //OTV__c is set to sum of lines that meet the OTV Criteria and are less than 12 months in each family
                //It is set to Prior Pure OTV unless the sum of ForecastedPureOTV < PriorPureOTV. Then set it to the sum of Forecasted Pure OTV.
        //ACV__c is set to OpptyAmount-OTV__C
        for(Opportunity oppty : System.Trigger.new) {
            
            if((oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId == mcOpptyRTId || oppty.RecordTypeId == opptyLockRTId || oppty.RecordTypeId == mcOpptyLockRTId) && !oppty.sfquote__Quote_Exists__c) { 
                if(oppty.StageName == BaseConstants.OPPTY_STAGE_DEAD_ATTRITION || oppty.StageName == BaseConstants.OPPTY_STAGE_DEADDUPE){
                    oppty.sfbase__OTV__c = 0.0;
                    oppty.sfbase__ACV__c = 0.0;
                    oppty.Amount = 0.0;
                } else {
                    if(countOfRecordsMap.get(oppty.Id) > 0) {
                        Boolean isOTVOppty = false;
                        Double opptyHybridAmount = 0.0;
                        if(renewalOpptyOTVMap != null){
                            RenewalOpptyUtil.RenewalOTVOppty renOTVOpp = renewalOpptyOTVMap.get(oppty.Id);
                            if(renOTVOpp != null){
                                oppty.sfbase__OTV__c = renOTVOpp.getPureOTVAmount();
                                oppty.sfbase__ACV__c = renOTVOpp.getOTVAmount()-renOTVOpp.getPureOTVAmount();
                                isOTVOppty = renOTVOpp.isOTV();
                                opptyHybridAmount = renOTVOpp.getOpptyAmount();
                            }
                        }
                        
                        if(isOTVOppty){
                            oppty.Amount = opptyHybridAmount;//calculated from OTV and ACV together based on if the OPSO is 
                        }else{
                            oppty.Amount = (oppty.sfbase__ForecastedAnnualContractValue__c < oppty.sfbase__PriorAnnualContractValue__c ? oppty.sfbase__ForecastedAnnualContractValue__c : oppty.sfbase__PriorAnnualContractValue__c);
                        }
                        system.debug(' oppty.Amount ::--::  '+oppty.Amount);
                    }
                }                
            }
        }

        if(!(opptyMap == null || opptyMap.isEmpty())){
            OpportunityContract__c[] opptyCtrs = [Select Id,ContractId__c,OpportunityId__c,ContractId__r.Status,ContractId__r.StatusCode,Relationship_Type__c From OpportunityContract__c Where OpportunityId__c IN :opptyMap.keySet()];
            for(OpportunityContract__c optyCtr: opptyCtrs){
                //Oppty Id already exists in the map
                if(opptyCtrsMap.containsKey(optyCtr.OpportunityId__c)){
                    OpportunityContract__c[] getCtrMap =opptyCtrsMap.get(optyCtr.OpportunityId__c);
                    getCtrMap.add(optyCtr);
                    opptyCtrsMap.put(optyCtr.OpportunityId__c,getCtrMap);
                }
                else{
                    //This is the first time we are see the Oppty id
                    opptyCtrsMap.put(optyCtr.OpportunityId__c,new OpportunityContract__c[]{optyCtr});
                }

            }
        }

        for (Id key : opptyMap.keySet()){
            for(Opportunity oppty : Trigger.new){
                if(oppty.Id == key){
                    boolean ctrExist = false;
                    OpportunityContract__c[] allCtrsforOppty =  opptyCtrsMap.get(key);
                    Id ctrId=opptyMap.get(key);
                    if(allCtrsforOppty !=null){
                        for(OpportunityContract__c optyCtr: allCtrsforOppty){
                        if(optyCtr.ContractId__c==ctrId){
                            ctrExist=true;
                            ctrsToUpdate.put(ctrId,oppty);
                            break;
                        }
                    }
                    }
                    //Throw an error if the selected contract doesnt belong to the assoc list. However, dont throw an error if we are trying to null out the field as part of the link contract to new oppty use case.
                    if(!ctrExist && ctrId != null)
                        oppty.addError(Label.REN_ERR_OPPTY_PRIOR_CTR);
                }
            }
        }

        if(!(ctrsToUpdate.isEmpty() || ctrsToUpdate ==null)){
           Contract[] ctrs= [Select Id,sfbase__RenewalStatus__c,ContractTerm,StatusCode,RenewalTerm,sfbase__CourtesyRenewalStartDate__c,AutoRenewCode, sfbase__ContractType__c,Status, EndDate From Contract Where Id IN :ctrsToUpdate.keySet()];

            for(Contract ctr: ctrs){
               Opportunity oppty=ctrsToUpdate.get(ctr.Id);
               if(!((oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId ==mcOpptyRTId || oppty.RecordTypeId == opptyLockRTId || oppty.RecordTypeId == mcOpptyLockRTId) && (oppty.StageName=='05 Closed' || oppty.StageName=='Dead - Duplicate' || oppty.StageName=='Dead Attrition'))){

                   if(ctr.sfbase__CourtesyRenewalStartDate__c !=null) {
                       oppty.StageName='Courtesy';
                   }
                   else if((ctr.StatusCode=='Activated' && (ctr.sfbase__ContractType__c=='Courtesy Contract' || ctr.sfbase__ContractType__c=='Courtesy Renewal'))) {
                       oppty.StageName='Courtesy';
                    }

                   else if((ctr.StatusCode=='Terminated' || ctr.StatusCode=='Expired') && (ctr.sfbase__RenewalStatus__c=='Renewed on Other Contract')) {
                        oppty.StageName='05 Closed';
                    }

                   else if((ctr.StatusCode=='Terminated' || ctr.StatusCode=='Expired') && (ctr.sfbase__RenewalStatus__c=='Did not renew')) {
                       oppty.StageName='Dead Attrition';
                   }

                   else if((ctr.StatusCode=='Terminated' || ctr.StatusCode=='Expired') && ctr.sfbase__RenewalStatus__c=='Contract Replacement')  {
                        oppty.StageName='Dead - Duplicate';
                    }

                    else if(ctr.AutoRenewCode =='Yes' && !(ctr.StatusCode=='Terminated') &&(oppty.sfbase__Contract_EndDate__c < ctr.EndDate))  {
                        oppty.sfbase__ForecastedContractTerm__c=ctr.RenewalTerm;
                        oppty.sfbase__Contract_EndDate__c=ctr.EndDate;
                        oppty.StageName='05 Closed';
                        // Quote Conversion will set the oppty close date if its running, so skip it here for that use case only
                        if(! BaseStatus.quoteConversionRunning) {
                                    oppty.CloseDate=ctr.EndDate;
                        }
                    }
                    else if(ctr.AutoRenewCode =='Yes' && !(ctr.StatusCode=='Terminated'))  {
                        oppty.sfbase__ForecastedContractTerm__c=ctr.RenewalTerm;
                        oppty.sfbase__Contract_EndDate__c=ctr.EndDate;
                    }
                    else{
                        oppty.sfbase__Contract_EndDate__c=ctr.EndDate;
                        oppty.sfbase__ForecastedContractTerm__c=ctr.ContractTerm;
                    }
                }
            }
        }
    } else if(Trigger.isUpdate && Trigger.isAfter && !BaseStatus.autoRenewalProcessRunning && !userLogin.startsWith(eimUtils.RENEWAL_USER_NAME)) {
        Map<Id, Opportunity> opptyQuotesIds = new Map<Id, Opportunity>();
        List<sfbase__OpportunityProductSummary__c> AdjustedOpsos = RenewalOpptyUtil.getAdjustedOpsos();
        boolean updateUnallocOPSO=false;
        Map<Id, Opportunity> oppWithQuoteIdMap = new Map<Id, Opportunity>();
        Set<Id> opptyIdSetDataQuality = new Set<Id>();

        AppConfig renewalOpportunityTriggerAppConfig = new appConfig();
        AppConfigRecord renewalUpliftSyncFeatureFlagAppConfigRecord = renewalOpportunityTriggerAppConfig.getValue(RENEWAL_UPLIFT_SYNC_FEATURE_FLAG);

        if(renewalUpliftSyncFeatureFlagAppConfigRecord != null){
            String renewalUpliftSyncFeatureFlag = renewalUpliftSyncFeatureFlagAppConfigRecord.value;
            if(!String.isBlank(renewalUpliftSyncFeatureFlag) && Boolean.valueOf(renewalUpliftSyncFeatureFlag)){
                RenewalOpportunityTriggerHandler.createRenewalOpptysKernelTasks(Trigger.oldMap, Trigger.newMap);
            }
        }

        for(Opportunity oppty : System.Trigger.New) {
            // if Quote Exist is true and hasOpptyProduct and Total value changes
            if((System.trigger.oldMap.get(oppty.Id).sfbase__Audited_Prior_ACV_value__c)!=oppty.sfbase__Audited_Prior_ACV_value__c){
                updateUnallocOPSO=true;
            }
            else if(!(oppty.StageName =='O5 Closed'|| oppty.StageName=='Dead Attrition' || oppty.StageName =='Dead - Duplicate')&& (oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId == mcOpptyRTId) && oppty.sfquote__Quote_Exists__c && oppty.HasOpportunityLineItem  && ((oppty.Amount != (System.trigger.oldMap.get(oppty.Id).Amount)) || (oppty.sfquote__Adjustment_Amount__c == (System.trigger.oldMap.get(oppty.Id).sfquote__Adjustment_Amount__c)) || (oppty.sfbase__ForecastedContractTerm__c != (System.trigger.oldMap.get(oppty.Id).sfbase__ForecastedContractTerm__c)))) {
                opptyQuotesIds.put(oppty.Id, oppty);
            }
            // if quote exists on the renewal opportunity having dead attrition stage for CSM / CSM Manager 
            // then consider the opportunity to make the amount zero by adjusting the opp adj product line
            if(!profileIdsSet.isEmpty() && profileIdsSet.contains(userProfileId)){
                if(oppty.StageName == BaseConstants.OPPTY_STAGE_DEAD_ATTRITION && (oppty.RecordTypeId == opptyRTId || oppty.RecordTypeId == opptyLockRTId) && oppty.Amount > 0){
                    if(oppty.sfquote__Quote_Exists__c){
                        oppWithQuoteIdMap.put(oppty.Id, oppty);
                    }
                }
            }
            // condition to check if the oppty criteria meets for Data Quality UPdate to create a task for rm when there is no red account attached
            // and forecasted attrition > 500k
            if(configDataValues != null && configDataValues.size() > 0 && 
                configDataValues.containsKey(FORECAST_ATTRITION_NAME) && configDataValues.get(FORECAST_ATTRITION_NAME) != null &&
                oppty.Forecasted_Attrition__c <= Decimal.valueOf(configDataValues.get(FORECAST_ATTRITION_NAME)) &&
                oppty.Forecasted_Attrition__c != Trigger.oldMap.get(oppty.Id).Forecasted_Attrition__c && 
                oppty.RecordTypeId == opptyRTId &&
                !(oppty.StageName == BaseConstants.OPPTY_STAGE_05_CLOSED || oppty.StageName == BaseConstants.OPPTY_STAGE_DEAD_ATTRITION) &&
                oppty.ForecastCategory != BaseConstants.OPPTY_FORCAST_CATEGORY_OMITTED &&
                (oppty.License_Renewal_Status__c == BaseConstants.LICENSE_RENEWAL_ATTRIT || oppty.License_Renewal_Status__c == BaseConstants.LICENSE_RENEWAL_REDUCE || oppty.License_Renewal_Status__c == BaseConstants.LICENSE_RENEWAL_ATTRIT_ACTIONABLE || oppty.License_Renewal_Status__c == BaseConstants.LICENSE_RENEWAL_REDUCE_ACTIONABLE) &&
                pricebookNameSet != null && pricebookNameSet.size() > 0 &&
                profileIdsSet != null && profileIdsSet.size()>0 && profileIdsSet.contains(userProfileId)){
                //accIdSet.add(oppty.AccountId);
                //opptyIdSetDataQuality.add(oppty.Id);
                conOpptyMapDataQuality.put(oppty.sfbase__PriorContractPrimary__c, oppty);
                system.debug('********************** conOpptyMapDataQuality:'+conOpptyMapDataQuality);
            } 
        }
        // process the opportunity to make the amount zero by adjusting the opp adj product line
        if(!oppWithQuoteIdMap.isEmpty()){
            RenewalOpportunityTriggerHandler.updateOppProductAdjLines(oppWithQuoteIdMap);
        }

        if(!(opptyQuotesIds.isEmpty() || opptyQuotesIds ==null)) {

            Map<Id,OpportunityLineItem[]> opptyProdMap = new Map<Id,OpportunityLineItem[]>();
            sfbase__OpportunityProductSummary__c[] opsos = [SELECT Id, sfbase__ProductFamily__c,CurrencyIsoCode ,sfbase__Opportunity__c,  sfbase__Opportunity__r.License_At_Risk_Reason__c, sfbase__Opportunity__r.ACV_Reason_Detail__c, sfbase__ForecastedRenewalQuantity__c, sfbase__ForecastedMonthlyOrderValue__c, sfbase__RMOverride__c, sfbase__ForecastedOTV__c, sfbase__ForecastedPureOTV__c 
                                                        FROM sfbase__OpportunityProductSummary__c
                                                        WHERE sfbase__Opportunity__c IN: opptyQuotesIds.keySet() ORDER BY sfbase__Opportunity__c];

            OpportunityLineItem[] opptyProds = [
                SELECT
                	ListPrice,
                    Quantity,
                    TotalPrice,
                    UnitPrice,
                    PricebookEntry.Product2.sfbase__SKU__c,
                    sfquote__Billing_Frequency__c,
                    PricebookEntry.Product2.sfbase__AdjustmentSKU__c,
                    PricebookEntry.Product2.sfbase__ProductFamily__c,
                    PricebookEntry.Product2.Bookings_Treatment__c,
                    OpportunityId, 
                    PricebookEntryId,PricebookEntry.Pricebook2Id,
                    PricebookEntry.Product2Id,
                    PricebookEntry.ProductCode,
                    sfquote__LineTermMonths__c,
                    sfquote__OTVCriteria__c,
                    PricebookEntry.Product2.PriceTreatment__c,
                    QuoteLine__r.Apttus_QPConfig__StartDate__c, 
                    QuoteLine__r.Apttus_Proposal__Proposal__r.SfdcService_Start_Date__c
                FROM OpportunityLineItem
                WHERE OpportunityId IN:opptyQuotesIds.keySet()
            ];
            
            //Group oppty Products by oppty Id's
            for(OpportunityLineItem opptyProd: opptyProds){
                //Oppty Id already exists in the map
                if(opptyProdMap.containsKey(opptyProd.OpportunityId)){
                    OpportunityLineItem[] getopptyProdMap = opptyProdMap.get(opptyProd.OpportunityId);
                    getopptyProdMap.add(opptyProd);
                    opptyProdMap.put(opptyProd.OpportunityId,getopptyProdMap);
                }
                else{
                    //This is the first time we are see the Oppty id
                    opptyProdMap.put(opptyProd.OpportunityId,new OpportunityLineItem[]{opptyProd});
                }
            }

            RenewalOpptyUtil opptyProcess = new RenewalOpptyUtil();
            List<sfbase__OpportunityProductSummary__c> updateOpsos= opptyProcess.groupOpptyProductFamily(opptyProdMap,opsos,opptyQuotesIds);
            System.debug('After groupOpptyProductFamily...' + updateOpsos);

            Map<Id, String> badOpptyMap = new Map<Id, String>();
            if(updateOpsos.size() > 0) {
                try {
                    System.debug('Just before updating the OPSOs');
                    update updateOpsos;
                    System.debug('Done updating OPSOs');
                } catch(System.DmlException ex) {
                    Integer i;
                    for(i=ex.getNumDml() - 1; i>=0; i--) {
                        //Get errored out Opso's oppty id
                        Id badOpptyId = updateOpsos.get(ex.getDmlIndex(i)).sfbase__Opportunity__c;
                        //Add to bad oppty id set with message for display/api
                        if(badOpptyMap.containsKey(badOpptyId)) {
                            String errMsg = badOpptyMap.get(badOpptyId);
                            errMsg += ex.getDmlMessage(i);
                            badOpptyMap.put(badOpptyId, errMsg);
                        } else {
                            badOpptyMap.put(badOpptyId, ex.getDmlMessage(i));
                        }
                        //Remove any problematic Opsos from the updated list
                        updateOpsos.remove(ex.getDmlIndex(i));
                    }
                    if(updateOpsos.size() > 0) {
                        //Try again to update with good ones
                        System.debug('Trying to update OPSO again...before updating the OPSOs');
                        update updateOpsos;
                        System.debug('Done updating the OPSOs second time');
                        
                    }
                    //add error to opptys where its opso updates have failed
                    for(Opportunity oppty : System.Trigger.New){
                        if(badOpptyMap.containsKey(oppty.Id)) {
                            System.debug('Update to Opportunity Summary Objects for the Opportunity ' + oppty.Id +
                                                ' failed with the following error: ' + badOpptyMap.get(oppty.Id));
                        }
                    }

                }

            }

        }

        List<sfbase__OpportunityProductSummary__c> updatedOpsos = RenewalOpptyUtil.getUpdatedOpsos();
        if(updatedOpsos.size() > 0) {
            Map<Id, String> badOpptyMap = new Map<Id, String>();
            try {
                update updatedOpsos;
            } catch(System.DmlException ex) {
                Integer i;
                for(i=ex.getNumDml() - 1; i>=0; i--) {
                    //Get errored out Opso's oppty id
                    Id badOpptyId = updatedOpsos.get(ex.getDmlIndex(i)).sfbase__Opportunity__c;
                    //Add to bad oppty id set with message for display/api
                    if(badOpptyMap.containsKey(badOpptyId)) {
                        String errMsg = badOpptyMap.get(badOpptyId);
                        errMsg += ex.getDmlMessage(i);
                        badOpptyMap.put(badOpptyId, errMsg);
                    } else {
                        badOpptyMap.put(badOpptyId, ex.getDmlMessage(i));
                    }
                    //Remove any problematic Opsos from the updated list
                    updatedOpsos.remove(ex.getDmlIndex(i));
                }
                if(updatedOpsos.size() > 0) {
                    //Try again to update with good ones
                    update updatedOpsos;
                }
                //add error to opptys where its opso updates have failed
                for(Opportunity oppty : System.Trigger.New){
                    if(badOpptyMap.containsKey(oppty.Id)) {
                        System.debug('Update to Opportunity Summary Objects for the Opportunity ' + oppty.Id +
                                            ' failed with the following error: ' + badOpptyMap.get(oppty.Id));
                    }
                }
            }
        }

        if(updateUnallocOPSO){
            if(AdjustedOpsos.size() > 0) {
                Map<Id, String> badOpptyMap = new Map<Id, String>();
                try {
                    insert AdjustedOpsos;
                } catch (System.DmlException ex) {
                    Integer i;
                    for(i=ex.getNumDml() - 1; i>=0; i--) {
                        //Get errored out Opso's oppty id
                        Id badOpptyId = AdjustedOpsos.get(ex.getDmlIndex(i)).sfbase__Opportunity__c;
                        //Add to bad oppty id set with message for display/api
                        if(badOpptyMap.containsKey(badOpptyId)) {
                            String errMsg = badOpptyMap.get(badOpptyId);
                            errMsg += ex.getDmlMessage(i);
                            badOpptyMap.put(badOpptyId, errMsg);
                        } else {
                            badOpptyMap.put(badOpptyId, ex.getDmlMessage(i));
                        }
                        //Remove any problematic Opsos from the updated list
                        AdjustedOpsos.remove(ex.getDmlIndex(i));
                    }
                    if(AdjustedOpsos.size() > 0) {
                        //Try again to update with good ones
                        update AdjustedOpsos;
                    }
                    //add error to opptys where its opso updates have failed
                    for(Opportunity oppty : System.Trigger.New){
                        if(badOpptyMap.containsKey(oppty.Id)) {
                            System.debug('Update to Opportunity Summary Objects for the Opportunity ' + oppty.Id +
                                                ' failed with the following error: ' + badOpptyMap.get(oppty.Id));
                        }
                    }
                }
            }

            List<sfbase__OpportunityProductSummary__c> AdjustedDelOpsos = RenewalOpptyUtil.getAdjustedDeleteOpsos();
            if(AdjustedDelOpsos.size() > 0) {
                Map<Id, String> badOpptyMap = new Map<Id, String>();
                try {
                    delete AdjustedDelOpsos;
                } catch (System.DmlException ex) {
                    Integer i;
                    for(i=ex.getNumDml() - 1; i>=0; i--) {
                        //Get errored out Opso's oppty id
                        Id badOpptyId = AdjustedDelOpsos.get(ex.getDmlIndex(i)).sfbase__Opportunity__c;
                        //Add to bad oppty id set with message for display/api
                        if(badOpptyMap.containsKey(badOpptyId)) {
                            String errMsg = badOpptyMap.get(badOpptyId);
                            errMsg += ex.getDmlMessage(i);
                            badOpptyMap.put(badOpptyId, errMsg);
                        } else {
                            badOpptyMap.put(badOpptyId, ex.getDmlMessage(i));
                        }
                        //Remove any problematic Opsos from the updated list
                        AdjustedDelOpsos.remove(ex.getDmlIndex(i));
                    }
                    if(AdjustedDelOpsos.size() > 0) {
                        //Try again to update with good ones
                        update AdjustedDelOpsos;
                    }
                    //add error to opptys where its opso updates have failed
                    for(Opportunity oppty : System.Trigger.New){
                        if(badOpptyMap.containsKey(oppty.Id)) {
                            System.debug('Update to Opportunity Summary Objects for the Opportunity ' + oppty.Id +
                                                ' failed with the following error: ' + badOpptyMap.get(oppty.Id));
                        }
                    }
                }
            }
        }
        // call the method to create a task for RM for data quality feature
        if(conOpptyMapDataQuality != null && conOpptyMapDataQuality.size()>0){

            Map<Id,Opportunity> conOpptyMapDataQualityFinalMap = new Map<Id,Opportunity>();

            for(Contract con : [Select Id, Pricebook2Id,Pricebook2.Name from Contract where Id IN : conOpptyMapDataQuality.keySet() and Pricebook2.Name like :pricebookNameSet]){
                conOpptyMapDataQualityFinalMap.put(con.Id,conOpptyMapDataQuality.get(con.Id));
                opptyIdSetDataQuality.add(conOpptyMapDataQuality.get(con.Id).Id);
            }

            if(conOpptyMapDataQualityFinalMap != null && conOpptyMapDataQualityFinalMap.size() > 0){
                RenewalOpportunityTriggerHandler.createTaskForNoRedAccount(conOpptyMapDataQualityFinalMap,opptyIdSetDataQuality);
            }
        }
    }
}