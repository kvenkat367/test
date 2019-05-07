/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: it_promop4 $
 * $Change: 9656785 $
 * $DateTime: 2015/01/05 16:14:04 $
 * $File: //it/applications/legal/freeze/Agreements/sfdc/src/triggers/AgmtDocusignRecipientBeforeTrigger.trigger $
 * $Id: //it/applications/legal/freeze/Agreements/sfdc/src/triggers/AgmtDocusignRecipientBeforeTrigger.trigger#3 $
 * $Revision: #3 $
 */

trigger AgmtDocusignRecipientBeforeTrigger on dsfs__DocuSign_Recipient_Status__c bulk(before insert, before update) {
	
	//see if the flag is true on insert
	//see if the flag is true on update
	//This trigger is only called before insert and update
	//Got an update on the call with Roya and Docusign team once the "SOP" goes to true it cannot go to false.	
	String[] allEnvelopeIds = new String[0]; 
	for(dsfs__DocuSign_Recipient_Status__c drs : Trigger.new) {
		if(drs.SignOnPaper__c){
		  allEnvelopeIds.add(drs.dsfs__Envelope_Id__c);	
		}
    }
    
    dsfs__DocuSign_Status__c[] allDSStatusRecs = [Select AgreementEnvelope__c from dsfs__DocuSign_Status__c where dsfs__Docusign_Envelope_Id__c IN :allEnvelopeIds];
    
    //Issue bulk update on agreement depending on their size.
    
	AgreementEnvelope__c[] updAgreementEnvs = new AgreementEnvelope__c[0];
	
	for(dsfs__DocuSign_Status__c ds:allDSStatusRecs){
		if(ds.AgreementEnvelope__c != null){
			boolean agmtIdAlreadyexists = false;
			if(updAgreementEnvs.size()>0){
				for(AgreementEnvelope__c agmt: updAgreementEnvs){
					if(ds.AgreementEnvelope__c == agmt.Id){
						agmtIdAlreadyexists = true;
					}
				}
			}
			if(!agmtIdAlreadyexists)
			   updAgreementEnvs.add(new AgreementEnvelope__c(Id = ds.AgreementEnvelope__c, SignedOnPaper__c = true));
		}
	}
	
	try{
		if (updAgreementEnvs.size()>0) update updAgreementEnvs;
	}catch(System.DmlException e){
		throw new AptsConstants.AgreementException('Error updating Agreement Envelope in AgmtDocusignRecipientBeforeTrigger:'+e.getMessage());
	}
	

}