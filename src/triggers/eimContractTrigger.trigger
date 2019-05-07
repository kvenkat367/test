trigger eimContractTrigger on Contract bulk(before insert, before update, after update, after insert) {
    //If the update to the contract is a result of another related object, then the below statement will yield true
    if(sfbase.OrderManagementUtils.canBypassTriggerExecution('Contract')) {
        return;
    }
    // If it is the VAT API user updating the Contract fields after the VIES call then bypass trigger execution.
    if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWithIgnoreCase(BaseConstants.VAT_API_USER)){
        return;
    }
    private final String CONVERSION_LOGIN = 'conversion_api@salesforce.com';
    private final String DUNNING_USER = 'billing@salesforce.com';
    //Fetching notification preferences
    Map<String,NotificationPreferences__c> renewalNotificationInformation = eimContract.getNotificationPreferences();   
    Map<Id,String> contractLanguageMap = new Map<Id,String>();

    if(UserInfo.getUserName() != null && (UserInfo.getUserName().startsWithIgnoreCase(CONVERSION_LOGIN) || UserInfo.getUserName().startsWithIgnoreCase(DUNNING_USER))){
        return;
    }
    String userLogin = UserInfo.getUserName();
    String userId = UserInfo.getUserId();
    //By pass trigger for these users
    if(userLogin.startsWith(eimUtils.ORDER_SUM_USER_NAME) || userLogin.startsWith(eimUtils.RENEWAL_USER_NAME) || BaseStatus.autoRenewalProcessRunning || userLogin.startsWith(eimUtils.DEAL_SUM_USER_NAME)) {
        return;
    }

    // If it is the VAT API user updating the Contract fields after the VIES call then bypass trigger execution.
    if(UserInfo.getUserName() != null && UserInfo.getUserName().startsWithIgnoreCase(BaseConstants.VAT_API_USER)){
        return;
    }

    // BEFORE UPDATE
    if(System.trigger.isUpdate && System.trigger.isBefore){
        for(Contract currContract : System.Trigger.new){
            Contract oldContract = Trigger.oldMap.get(currContract.Id);

            //Populate Renewal Notification Days field for contracts
            eimContract.updateRenewalNotificationDays(currContract, renewalNotificationInformation);

        }
    }

    if(System.trigger.isBefore) {
        if(System.trigger.isInsert) {
            //price list to price book mapping for manual contracts
            ContractTriggerPriceListHelper contractPriceListHelper = new  ContractTriggerPriceListHelper(Trigger.new,null,false);
            contractPriceListHelper.execute();

            for(Contract sglContract:System.trigger.new) {

                // In LEX, when an Activated Contract is cloned, the new clone page Status is defaulted to Activated instead of Draft, Hence making the change below
                sglContract.Status = 'Draft';

                //Null Initial_Contract_End_Date__c on clone...the value is anyways set only during contract activation
                sglContract.Initial_Contract_End_Date__c = null;
                sglContract.LastRenewalNotificationDate__c = null;
                sglContract.SuppressAutoRenewalNotification__c =false;
                sglContract.sfdcOriginalContractTerm__c = sglContract.ContractTerm;
                //Clearing the Dunning, Decline and Org Suspension Process fields. There is no sfdc contract trigger
                // in billing package, hence making the changes here.
                sglContract.NextSuspensionDate__c = null;
                sglContract.DeclinePaymentsCounter__c = null;
                sglContract.NextDunningDate__c = null;
                sglContract.DeclineNotification__c = null;
                sglContract.LastDeclineNotificationDate__c = null;
                sglContract.InvoiceBalanceDue__c = 0.00;
                sglContract.LevelThreeEligible__c = false;
                eimContract.setContractInitialAutoRenewalAndEndDate(sglContract);
                //Null and Populate Renewal Notification Days field from custom setting
                sglContract.RenewalNotificationDays__c = null;
                eimContract.updateRenewalNotificationDays(sglContract, renewalNotificationInformation);
            }
        }

        //to check if contract currency is the same as pricebook currency for CPQ contracts
        if(System.trigger.isInsert || System.trigger.isUpdate)
        {
            Set<Id> contractPricebookIds = new Set<Id>();
            for(Contract currContract: System.trigger.new)
            {
                contractPricebookIds.add(currContract.Pricebook2Id);
            }
            Map<Id,Pricebook2> pricebookMap = new Map<Id,Pricebook2>([SELECT Id,CurrencyIsoCode FROM Pricebook2 WHERE Id in: contractPricebookIds AND IsNewPriceBook__c = true AND Name LIKE '%CPQ%']);
            for(Contract currContract: System.trigger.new)
            {
                if(null!=pricebookMap.get(currContract.Pricebook2Id))
                {
                    if(!(currContract.CurrencyIsoCode.equals((pricebookMap.get(currContract.Pricebook2Id)).CurrencyIsoCode)))
                    {
                        currContract.addError(Label.OM_ERROR_CONTRACT_AND_PRICEBOOK_CURRENCIES_MISMATCH);
                    }
                }
                if(System.trigger.isUpdate && currContract.sfdcOriginalContractTerm__c != System.trigger.oldMap.get(currContract.Id).sfdcOriginalContractTerm__c && currContract.Status == 'Activated'){
                    currContract.sfdcOriginalContractTerm__c.addError(Label.OM_ERROR_CANNOT_CHANGE_ORIGINAL_CONTRACT_TERM);
                }
            }
        }

        // extended contract info
        Map<Id,Contract> extendedContractInfo = null;
        if(System.trigger.isUpdate) {
            Set<Id> draftContractsIds = new Set<Id>();
            Set<Id> contractsWithOrders = new Set<Id>();

            //price list to price book mapping for manual contracts
            ContractTriggerPriceListHelper contractPriceListHelper = new  ContractTriggerPriceListHelper(Trigger.new,Trigger.oldMap,true);
            contractPriceListHelper.execute();

            for(Contract sglContract:System.trigger.new) {
                Contract oldContract = Trigger.oldMap.get(sglContract.Id);
                if(eimOrderAPS.checkCustomPaymentInfoChanged(oldContract, sglContract)) {
                    sglContract.addError(Label.OM_ERROR_CUSTOM_PAYMENT_CHANGED);
                }
                if(sglContract.UpdateContext__c != null && sglContract.UpdateContext__c.equals('CYBS')) {
                    sglContract.UpdateContext__c = null;
                }
                // if this is termination event, check to make sure all available qty is 0
                if(sglContract.Status.startsWith('Terminated') &&
                   System.trigger.oldMap.get(sglContract.Id).Status == 'Activated') {

                       if ( sglContract.sfbase__RenewalStatus__c == null &&
                           sglContract.sfbase__ContractType__c != 'Courtesy renewal' )
                           sglContract.addError(Label.OM_CONTRACT_ERROR_Renewal_status_null);

                       // search for order lines with positive add qty
                       OrderItem[] unreducedOrderItems = [select Id from OrderItem where   Order.ContractId =: sglContract.Id AND
                                                          sfbase__AvailableQuantity__c > 0 AND
                                                          Order.StatusCode = 'A' AND
                                                          PricebookEntry.BillingFrequency > 0];
                       if (unreducedOrderItems.size() > 0) {
                           sglContract.addError(Label.OM_ERROR_Contract_Termination_Avail_Qty);

                       }
                   }
                if(sglContract.Status == 'Activated' &&
                   System.trigger.oldMap.get(sglContract.Id).Status != 'Activated') {
                       if (!BaseStatus.quoteConversionRunning){
                           if(extendedContractInfo == null) {
                               extendedContractInfo = new Map<Id,Contract>([SELECT Id, Account.sfbase__DisableContractActivation__c,Pricebook2.name
                                                                            FROM Contract WHERE Id in: System.trigger.new]);
                           }
                           if(extendedContractInfo.get(sglContract.Id).Account.sfbase__DisableContractActivation__c) {
                               sglContract.addError(Label.OM_ERROR_ACCOUNT_INVALID);
                           }
                       }

                       if((sglContract.BillingEmail == null || sglContract.BillingEmail == '') &&
                          sglContract.sfbase__ContractType__c != 'Courtesy Contract') {
                              sglContract.addError(Label.OM_ERROR_CONTRACT_ENTER_BILLING_EMAIL);
                          }
                       // sync the contract original term only at activation if it is not inline with the contract term.
                       if(sglContract.sfdcOriginalContractTerm__c != sglContract.ContractTerm){
                           sglContract.sfdcOriginalContractTerm__c = sglContract.ContractTerm;
                       }
                   }

                // if contract is not in Draft status, do not allow updates to term
                if(!UserInfo.getUserName().startsWith(eimUtils.RENEWAL_USER_NAME) && !BaseStatus.autoRenewalProcessRunning &&
                   sglContract.Status != 'Draft') {

                       if (sglContract.ContractTerm != System.trigger.oldMap.get(sglContract.Id).ContractTerm) {
                           sglContract.ContractTerm.addError(Label.OM_ERROR_Contract_Term_Non_Draft);
                       }

                   }

                //validations for contract start date and pricebook2 - This validation is by-passed by conversion user.
                if(sglContract.StatusCode != 'Draft' && sglContract.StatusCode != 'In Approval Process'){
                    if(sglContract.startDate == null || sglContract.startDate != System.trigger.oldMap.get(sglContract.Id).startDate){
                        sglContract.StartDate.addError(Label.OM_ERROR_INVALID_CHANGE_IN_CONTRACT_START_DATE);
                    }

                    if(sglContract.Pricebook2Id  == null || sglContract.Pricebook2Id != System.trigger.oldMap.get(sglContract.Id).Pricebook2Id){
                        sglContract.addError(Label.OM_ERROR_INVALID_CHANGE_IN_CONTRACT_PRICEBOOK);
                    }

                }
            }
            //Create a unique list of account Ids
            Set<Id> acctIds = new Set<Id>();

            List<Contract> terminatedContracts = new List<Contract>();
            for(Contract sglContract:System.trigger.new) {
                if(!System.trigger.oldMap.get(sglContract.Id).Status.startsWith('Terminated')
                   && sglContract.Status.startsWith('Terminated')) {
                       acctIds.add(sglContract.AccountId);
                       terminatedContracts.add(sglContract);
                       sglContract.sfbase__COSOUpdateRequired__c = true;
                   }

                if (System.trigger.oldMap.get(sglContract.id).status.startsWith('Draft') &&
                    System.trigger.oldMap.get(sglContract.id).pricebook2id != System.trigger.newMap.get(sglContract.id).pricebook2id) {
                        draftContractsIds.add(sglContract.id);
                    }
            }
            if(terminatedContracts.size() > 0) {
                //update entitlement end date
                EntitlementBaseUtils.updateEntitlementEndDate(terminatedContracts);
            }
            if (draftContractsIds.size() > 0) {
                List<Order> orders = [select contractid from order where contractid in :draftContractsIds];

                for (Order order : orders){
                    contractsWithOrders.add(order.contractid);
                }
            }

            Set<Id> ExpContracts = new Set<Id>();

            for ( Contract sglContract:System.trigger.new) {
                //Added when analysing bug# W-1763985 - Contracts will be expired by both Provisioning Process and Contract Expiration Process.
                if ( eimUtils.IsProvisioningUser(userId) || userLogin.startsWith(eimUtils.CONTRACT_EXPIRATION_USER_NAME)) {
                    //create a set of contract ids
                    if ( sglContract.Status == 'Expired'  && System.trigger.oldMap.get(sglContract.Id).Status != 'Expired'
                        && sglContract.sfbase__RenewalStatus__c == 'Did not renew') {
                            ExpContracts.add(sglContract.Id);
                        } else if(sglContract.Status == 'Expired' && System.trigger.oldMap.get(sglContract.Id).Status != 'Expired'
                                  && sglContract.sfbase__RenewalStatus__c == 'Contract Replacement') {
                                      sglContract.sfbase__COSOUpdateRequired__c = true;
                                  }
                }
                else { // this is when user edit the expire contrcats using VF page.
                    if ( sglContract.Status == 'Expired' && System.trigger.oldMap.get(sglContract.Id).sfbase__RenewalStatus__c != 'Did not renew' && sglContract.sfbase__RenewalStatus__c == 'Did not renew') {
                        ExpContracts.add(sglContract.Id);
                    }
                    eimContract.setContractInitialAutoRenewalAndEndDate(sglContract,System.trigger.oldMap.get(sglContract.Id));

                }

                if (contractsWithOrders.contains(sglContract.id))
                    sglContract.addError(Label.OM_ERROR_ON_DRAFT_CONTRACT_PB);

            }
            if ( ExpContracts.size() > 0 ) {
                eimOrderAPS.setCommissionStatus(ExpContracts, System.trigger.newMap, userId);
            }
        }
    }

    // after update
    else if (System.Trigger.isAfter && System.Trigger.isUpdate){
        eimDispatcher.runDispatcher(System.trigger.new, System.trigger.oldMap);

        if(!eimUtils.isFullBypassUser(userLogin)) {
            //RMS SELA Contract Update changes
            Boolean updatedSuccessfully = false;
            List<String> contractIds = new List<String>();
            String oldSelaValue;
            String newSelaValue;
            for(Contract currContract: System.trigger.new)
            {
                oldSelaValue = System.trigger.oldMap.get(currContract.id).SELA_Contract__c;
                newSelaValue = currContract.SELA_Contract__c;

                if(ContractTriggerHelper.eligibleForSelaEvaluation(oldSelaValue,newSelaValue))
                {
                    contractIds.add(currContract.Id);
                }
            }
            if(contractIds.size() > 0)
            {
                System.debug('eimContractTrigger: contractIds List: '+contractIds);
                ContractTriggerHelper.updateOrderAndOrderItems(contractIds);
                System.debug('Order and Order Items updated successfully');
            }
        }
    }

    else if (System.trigger.isInsert && System.trigger.isAfter){
        for(Contract currContract: System.trigger.new)
        {
            //Create Special Terms for all types of Contract.
            if (!BaseConstants.STR_QUOTE_CONVERSION.equalsIgnorecase(currContract.sfbase__ContractCreationSource__c))
                contractLanguageMap.put(currContract.Id, BaseUtil.getLanguageBasedOnCode(currContract.BillingLanguage));
        }
        //System.debug('*** ContractLanguage Map: ****'+contractLanguageMap.values().size());

        // Create Contract Special Terms for manual flow
        ContractTriggerHelper.createContractSpecialTerms(contractLanguageMap);

    }
    // Check if the contracts require VAT validation or Contact Roles related updates
    if(System.Trigger.isBefore){
        // Insert trigger
        if(System.Trigger.isInsert){
            // VAT Validation
            ContractTriggerHelper.vatValidationProcess(System.trigger.new, true, null);
        }
        // Update trigger
        else if(System.Trigger.isUpdate){
            // VAT Validation
            ContractTriggerHelper.vatValidationProcess(System.trigger.new, false, System.trigger.oldMap);
            // Contact Roles related checks not needed while processing high quote lines
            if(!Basestatus.processingHighQuoteLines){
		            // Check if Contact Roles global switch is enabled
		            AppConfig appConfig = new AppConfig();
		            AppConfigRecord contactRolesSettings = appConfig.getValue('ContactRoles.isEnabled');
		            if(contactRolesSettings != null && contactRolesSettings.value == 'true'){
		                List<Id> deleteInactiveContactRolesForContracts = new List<Id>();
		                List<Id> removeRolesForContracts = new List<Id>();
		                List<Contract> updateContactRolesForContracts = new List<Contract>();
		                Set<Id> contractIdsToLog = new Set<Id>();
				//Fetch Foundation RecordTypeId 
                                Id foundationRecordTypeId = ContactRoleType.getContractRecordTypeId('Foundation');
		                for(Contract contract : System.trigger.new){
				    //ignore if current contract record type is Foundation 
                                    if (contract.RecordTypeId == foundationRecordTypeId || contract.BillingEmail == null){
                                         continue; 
                                    }
		                    Contract oldContract = System.trigger.oldMap.get(contract.Id);
		                    // Delete inactive Contact Roles on Contract activation through the async process
		                    if(oldContract.Status != contract.Status && oldContract.Status == 'Draft' && contract.Status == 'Activated'){
		                        deleteInactiveContactRolesForContracts.add(contract.Id);
		                    }
		                    // Remove Payment Card Holder Contact Roles on Contract through the async process, if the payment method
		                    // changed from CreditCard or DirectDebit to Check or WireTransfer
		                    if(oldContract.sfbase__PaymentType__c != contract.sfbase__PaymentType__c &&
		                       (oldContract.sfbase__PaymentType__c == 'CreditCard' || oldContract.sfbase__PaymentType__c == 'DirectDebit')
		                       && (contract.sfbase__PaymentType__c == 'Check' || contract.sfbase__PaymentType__c == 'WireTransfer')){
		                           removeRolesForContracts.add(contract.Id);
		                       }
		                    // Check if the Async process call should be skipped, in scenarios where the contract trigger was
		                    // initiated by Contact Role creation or updation.
		                    if(!ContactRolesFactory.skipContactRoleAsyncProcess){
		                        // Update Primary Billing Contact Role for the Contract through the async process
		                        // if any of the Billing related fields have changed
		                        if(oldContract.BillingFirstName != contract.BillingFirstName || oldContract.BillingLastName != contract.BillingLastName
		                           || oldContract.BillingEmail != contract.BillingEmail){
		                               updateContactRolesForContracts.add(contract);
		                               contractIdsToLog.add(contract.Id);
		                           }
		                    }
		                }
		                ContactRolesAsyncUtility contactRolesAsyncUtility = new ContactRolesAsyncUtility();
		                // Check if there are Contracts that could have inactive Contact Roles that needs to be deleted
		                if(deleteInactiveContactRolesForContracts.size() > 0){
		                    contactRolesAsyncUtility.deleteInactiveContactRolesForContracts = deleteInactiveContactRolesForContracts;
		                }
		                // Check if there are Contracts for which the Payment Card Holder role needs to be removed
		                if(removeRolesForContracts.size() > 0){
		                    contactRolesAsyncUtility.removeRolesForContracts = removeRolesForContracts;
		                }
		                // Check if there are Contracts that have billing fields updated, so that the Contact Roles also needs to be updated
		                if(updateContactRolesForContracts.size() > 0){
		                    contactRolesAsyncUtility.updateContactRolesForContracts = updateContactRolesForContracts;
		                }
		                // Check if the aysnc job can be added to avoid reaching the limit
		                if(System.Limits.getQueueableJobs() == System.Limits.getLimitQueueableJobs()){
		                    System.debug('Reached the max limit for queuable jobs, so the update logic for Contact Roles will not be executed.');
		                    contractIdsToLog.addAll(removeRolesForContracts);
		                    contractIdsToLog.addAll(deleteInactiveContactRolesForContracts);
		                    // Execute logic from a schedulable class to log the event
		                    // where contact role insert or update could not be done
		                    // ContactRolesUtility.logMessage(contractIdsToLog, 'Before Update');
		                }
		                else{
		                    Id asyncJobID = System.enqueueJob(contactRolesAsyncUtility);
		                    System.debug('ID for async process to update contact roles (Primary Billing Contact or Payment Card Holder) : '+ asyncJobID);
		                }
		            }
		        }
        }
    }
    // Contact Roles related checks not needed while processing high quote lines
    if(!Basestatus.processingHighQuoteLines){
		    // Check if the contract needs to have a Primay Billing Contact role created
		    if(System.Trigger.isAfter){
		        if(System.Trigger.isInsert){
		            // Check if Contact Roles global switch is enabled
		            AppConfig appConfig = new AppConfig();
		            AppConfigRecord contactRolesSettings = appConfig.getValue('ContactRoles.isEnabled');
		            if(contactRolesSettings != null && contactRolesSettings.value == 'true'){
		                List<Contract> createContactRolesForContracts = new List<Contract>();
		                // For all Contracts, create a Primary Billing Contact.
		                Set<Id> contractIdsToLog = new Set<Id>();
				//Fetch Foundation RecordTypeId 
                                Id foundationRecordTypeId = ContactRoleType.getContractRecordTypeId('Foundation');
		                for(Contract contract : System.trigger.new){
				//ignore if current contract record type is Foundation 
                                if (contract.RecordTypeId == foundationRecordTypeId || contract.BillingEmail ==null){
                                     continue; 
                                }
		                    // Add the Contracts to a list to create Contact Roles
		                    createContactRolesForContracts.add(contract);
		                    contractIdsToLog.add(contract.Id);
		                }
		                // Check if the aysnc job can be added to avoid reaching the limit
		                if(System.Limits.getQueueableJobs() == System.Limits.getLimitQueueableJobs()){
		                    System.debug('Reached the max limit for queuable jobs, so the insert logic for Contact Roles will not be executed.');
		                    // Execute logic from a schedulable class to log the event
		                    // where contact role insert or update could not be done
		                    // ContactRolesUtility.logMessage(contractIdsToLog, 'After Insert');
		                }
		                else{
		                    ContactRolesAsyncUtility contactRolesAsyncUtility = new ContactRolesAsyncUtility();
		                    contactRolesAsyncUtility.createContactRolesForContracts = createContactRolesForContracts;
		                    Id asyncJobID = System.enqueueJob(contactRolesAsyncUtility);
		                    System.debug('ID for async process to create contact role (Primary Billing Contact) : '+ asyncJobID);
		                }
		            }
		        }
		    }
    }
}