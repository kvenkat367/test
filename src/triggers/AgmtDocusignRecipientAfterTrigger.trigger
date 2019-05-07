/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: anoop.singh $
 * $Change:  $
 * $DateTime: 2011/03/02 10:39:38 $
 * $File: //it/applications/agreementsmgmt/main/sfdc/src/triggers/AgmtDocusignRecipientAfterTrigger.trigger $
 * $Id: //it/applications/agreementsmgmt/main/sfdc/src/triggers/AgmtDocusignRecipientAfterTrigger.trigger#1 $
 * $Revision: #1 $
 */

trigger AgmtDocusignRecipientAfterTrigger on dsfs__DocuSign_Recipient_Status__c bulk(after insert, after update) {
	
	//This trigger is only called after insert and update
	String[] negCompletedDSRecipients = null;
	String[] nonNegCompletedDSRecipients = null;
	Map<String, String[]> negCompletedDSRecipientsMap = new Map<String, String[]>();
	Map<String, String[]> nonNegCompletedDSRecipientsMap = new Map<String, String[]>();
	String[] completedEnvelopeIds = new String[0];
	if(Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {	
		for(dsfs__DocuSign_Recipient_Status__c drs : Trigger.new) {
			if(drs.dsfs__Date_Signed__c != null && drs.dsfs__Recipient_Status__c == AptsConstants.DOCUSIGNSTATUS_COMPLETED){
				completedEnvelopeIds.add(drs.dsfs__Envelope_Id__c);
				if(drs.dsfs__DocuSign_Routing_Order__c == 2) {
					negCompletedDSRecipients = negCompletedDSRecipientsMap.get(drs.dsfs__Envelope_Id__c);
					if(negCompletedDSRecipients == null) {
						negCompletedDSRecipients = new String[0];
					}
					negCompletedDSRecipients.add(drs.dsfs__DocuSign_Recipient_Id__c);
					negCompletedDSRecipientsMap.put(drs.dsfs__Envelope_Id__c, negCompletedDSRecipients);
				}
				else if(drs.dsfs__DocuSign_Routing_Order__c == 1) {
					nonNegCompletedDSRecipients = nonNegCompletedDSRecipientsMap.get(drs.dsfs__Envelope_Id__c);
					if(nonNegCompletedDSRecipients == null) {
						nonNegCompletedDSRecipients = new String[0];
					}
					nonNegCompletedDSRecipients.add(drs.dsfs__DocuSign_Recipient_Id__c);
					nonNegCompletedDSRecipientsMap.put(drs.dsfs__Envelope_Id__c, nonNegCompletedDSRecipients);
				}			
			}
	    }
	}
	
    //Issue bulk update on agreement envelope.
    dsfs__DocuSign_Status__c[] completedDSStatusRecs = [Select AgreementEnvelope__c from dsfs__DocuSign_Status__c where dsfs__Docusign_Envelope_Id__c IN :completedEnvelopeIds];
	AgreementEnvelope__c[] updCompletedAgreementEnvs = new AgreementEnvelope__c[0];
	Integer counter = 0;
	for(dsfs__DocuSign_Status__c ds:completedDSStatusRecs){
		if(ds.AgreementEnvelope__c != null){
			AgreementEnvelope__c agmtEnv = [Select Id, Agreement__c, DocuSignEnvelopeId__c from AgreementEnvelope__c where id = :ds.AgreementEnvelope__c limit 1];
			Apttus__APTS_Agreement__c agmt = [select Apttus__Non_Standard_Legal_Language__c from Apttus__APTS_Agreement__c where id = :agmtEnv.Agreement__c];
			if (agmt != null) {
				if(agmt.Apttus__Non_Standard_Legal_Language__c) {
					negCompletedDSRecipients = negCompletedDSRecipientsMap.get(agmtEnv.DocuSignEnvelopeId__c);
					if(negCompletedDSRecipients != null) {
						agmtEnv.DocuSign_Recipient_Id__c = negCompletedDSRecipients[0];
						updCompletedAgreementEnvs.add(agmtEnv);
					}
				}
				else{
					nonNegCompletedDSRecipients = nonNegCompletedDSRecipientsMap.get(agmtEnv.DocuSignEnvelopeId__c);
					if(nonNegCompletedDSRecipients != null) {
						agmtEnv.DocuSign_Recipient_Id__c = nonNegCompletedDSRecipients[0];
						updCompletedAgreementEnvs.add(agmtEnv);
					}
				}
			}
		}
		//counter++;
	}
	if(Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {	
		try{
			if (updCompletedAgreementEnvs.size() > 0) {
				System.debug('Updating Agreement Envelope with Docusign recipient ID');
				update updCompletedAgreementEnvs;
			}
		}catch(System.DmlException e){
			throw new AptsConstants.AgreementException('Error updating Agreement Envelope with DocuSign_Recipient_Id__c in AgmtDocusignRecipientAfterTrigger:'+e.getMessage());
		}
	}

}