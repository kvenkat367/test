/*
 * RelEng Perforce/RCS Header - D+
 * $Author: gmalik $
 * $Change: 858739 $
 * $DateTime: 2008/11/24 19:34:55 $
 * $File: //store/190/patch/om/sfdc/src/triggers/ContractSpecialTermsTrigger.trigger $
 * $Id: //store/190/patch/om/sfdc/src/triggers/ContractSpecialTermsTrigger.trigger#1 $
 * $Revision: #1 $
 */

/*
 * This trigger will populate the original contract term on all contracts
 * This is temporary trigger and will be inactivated after all existing contracts will have value
 * 
 */ 
trigger ContractOriginalTermTrigger on Contract bulk(before update){
      //populate original contract term for the contracts
    if(System.trigger.isUpdate && System.trigger.isBefore){
             ContractOriginalTermHelper.populateContractOriginalTerm(System.trigger.new);
    }
}