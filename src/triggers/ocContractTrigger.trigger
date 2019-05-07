/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: sjain $
 * $Change: 499705 $
 * $DateTime: 2007/12/04 18:25:32 $
 * $File: //store/billing/100/apex/sfdc/ocContractTrigger.apex $
 * $Id: //store/billing/100/apex/sfdc/ocContractTrigger.apex#1 $
 * $Revision: #1 $
 */

trigger ocContractTrigger on Contract bulk(before insert) {

	/*
	 * Initializing the Map  for countryRevMap and sobPaymentRevenueMap custom objects
	 */
	Map<String, sfbase__CountryRevenueMap__c> 	countryRevMap 			= new Map<String, sfbase__CountryRevenueMap__c>();
	Set<String> 								countryList 			= new Set<String>();

	public final String ORDER_CENTER_USER_ID = '00530000000borPAAQ';

	/*
	* Call the contract validation code before  insert and update of contarct.
	* It populates the Map with country ISO codes as key and with sfbase__CountryRevenueMap__c as value.
	* It populates the Map with renenu owner as key and with sfbase__SOBPaymentMethodMap__c as value.
	* Fecth the contracts which are Finalized
	* All the validating methods are called from this single method
	*/

	System.debug('*** Before executing ***');

    if(UserInfo.getUserId() == ORDER_CENTER_USER_ID ){
		if(System.trigger.isBefore){

			System.debug('*** During execution ***');

			Set<String> contractIdArr = new Set<String>();

			//Fetching the CountryRevenueMap data
			for(Contract thisContract : 	System.Trigger.new){

				countryList.add(thisContract.BillingCountry);

			}

			//setting the Map for sfbase__CountryRevenueMap__c custom object
			for(sfbase__CountryRevenueMap__c countryRevAr :[select sfbase__CountryISOCode__c,
																	sfbase__CountryName__c,
																	sfbase__PrimaryCurrency__c,
																	sfbase__RevenueOwner__c,
																	sfbase__RevenueRegion__c,
																	sfbase__SupportedCurrencies__c,
																	sfbase__VATNumberRequired__c
															from  sfbase__CountryRevenueMap__c
															where sfbase__CountryISOCode__c in :countryList]){
				countryRevMap.put(countryRevAr.sfbase__CountryISOCode__c,countryRevAr);
			}

			for(Contract currContract : System.Trigger.new) {
				
				sfbase__CountryRevenueMap__c    conRevenueOwner = countryRevMap.get(currContract.BillingCountry);
				
				if(conRevenueOwner!= null) {
					System.debug('*** Setting values ***');
					currContract.sfbase__RevenueOwner__c = conRevenueOwner.sfbase__RevenueOwner__c;
					currContract.sfbase__RevenueRegion__c = conRevenueOwner.sfbase__RevenueRegion__c;
				}
			}
        }
	}
}