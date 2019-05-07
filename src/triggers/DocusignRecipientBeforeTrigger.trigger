/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: release $
 * $Change: 1426491 $
 * $DateTime: 2010/08/27 14:46:48 $
 * $File: //store/main/quote/sfdc/src/triggers/DocusignRecipientBeforeTrigger.trigger $
 * $Id: //store/main/quote/sfdc/src/triggers/DocusignRecipientBeforeTrigger.trigger#2 $
 * $Revision: #2 $
 */

trigger DocusignRecipientBeforeTrigger on dsfs__DocuSign_Recipient_Status__c(before insert, before update, after update) {
//********************************************************************************************************** 
	// Firest on before insert and before update
	//Quote/Order update when SignOnPaper__c flag is set on dsfs__DocuSign_Recipient_Status__c
//**********************************************************************************************************	
	if (trigger.isBefore) {
		//This trigger is only called before insert and update
		//Got an update on the call with Roya and Docusign team once the "SOP" goes to true it cannot go to false.	
		String[] allEnvelopeIds = new String[0]; 
		for(dsfs__DocuSign_Recipient_Status__c drs : Trigger.new) {
			if(drs.SignOnPaper__c){
			  allEnvelopeIds.add(drs.dsfs__Envelope_Id__c);	
			}
	    }
  
	    dsfs__DocuSign_Status__c[] allDSStatusRecs = [Select SfdcProposal__c, Order__c from dsfs__DocuSign_Status__c where dsfs__Docusign_Envelope_Id__c IN :allEnvelopeIds];
	    
	    //Issue bulk update on quote and order depending on their size.
		Apttus_Proposal__Proposal__c[] updQuotes = new Apttus_Proposal__Proposal__c[0];
		Order[] updOrders = new Order[0];
		
		for(dsfs__DocuSign_Status__c ds:allDSStatusRecs){
			if(ds.SfdcProposal__c != null){
				boolean qteIdAlreadyexists = false;
				if(updQuotes.size()>0){
					for(Apttus_Proposal__Proposal__c qte: updQuotes){
						if(ds.SfdcProposal__c == qte.Id){
							qteIdAlreadyexists = true;
						}
					}
				}
				if(!qteIdAlreadyexists)
				   updQuotes.add(new Apttus_Proposal__Proposal__c(Id = ds.SfdcProposal__c, SfdcSignedOnPaper__c = true));
			}
			if(ds.Order__c != null){
				boolean ordIdAlreadyexists = false;
				if(updOrders.size()>0){
					for(Order ord: updOrders){
						if(ds.Order__c == ord.Id){
							ordIdAlreadyexists = true;
						}
					}
				}
				if(!ordIdAlreadyexists)
				   updOrders.add(new Order(Id = ds.Order__c, sfbase__SignedOnPaper__c = true));
			}
		}
		
		try{
			if (updQuotes.size()>0) update updQuotes;
			if (updOrders.size()>0) update updOrders;	
		}catch(System.DmlException e){
			throw new sfquote.Quote.QuoteCreationException('Error updating Order or Quotes in DocusignRecipientBeforeTrigger:' + e.getMessage());
		}
	}

//********************************************************************************************************** 
	//Fires after update
	//Find if there are any Docusign Recipients who have signed the envelope but have missing ContactId.
	//This scenario could happen during envelope reassign using "Change Signer"		
//**********************************************************************************************************		
	if(Trigger.isAfter) {
		if (Trigger.isUpdate) {
			//Find all the recipients completed signing related to Quote/Proposal.  Authority level condition removes internal counter signers
			Set<Id> recipients = new Set<Id>();
			for(dsfs__DocuSign_Recipient_Status__c drs : Trigger.New) {
				if (drs.dsfs__Recipient_Status__c.equalsIgnoreCase('Completed')
					    && drs.dsfs__Date_Signed__c != null
					    && String.isNotBlank(drs.DS_Authority_Level__c)
						&& String.isBlank(drs.dsfs__Contact__c)) {
					recipients.add(drs.Id);
				}
			}

			if(!recipients.isEmpty()) {
				List<dsfs__DocuSign_Recipient_Status__c> completedRecipientsWithNoContactId = SfdcPublishQuoteDao.getCompletedDocuSignRecipients(recipients);
				Map<String,String> signerEmails = new Map<String,String> ();
				for(dsfs__DocuSign_Recipient_Status__c drs : completedRecipientsWithNoContactId) {
					if (String.isNotBlank(drs.dsfs__Parent_Status_Record__r.SfdcProposal__c)) {
						signerEmails.put(drs.dsfs__Parent_Status_Record__r.SfdcProposal__r.Apttus_Proposal__Account__c + '|' + drs.dsfs__DocuSign_Recipient_Email__c,drs.dsfs__DocuSign_Recipient_Email__c);
					}
				}
			
				Map <String,Contact> contacts = SfdcPublishQuoteDao.getContactDataFromEmailAddresses(signerEmails.values());
				List<Contact> newContacts = new List<Contact>();
				for(dsfs__DocuSign_Recipient_Status__c signer : completedRecipientsWithNoContactId) {
					if (contacts.get(signer.dsfs__Parent_Status_Record__r.SfdcProposal__r.Apttus_Proposal__Account__c + '|' + signer.dsfs__DocuSign_Recipient_Email__c) == null) {
						String[] names = UserInfoUtil.getFirstNameLastNameFromFullName(signer.Name);
						Contact c = new Contact(AccountId = signer.dsfs__Parent_Status_Record__r.SfdcProposal__r.Apttus_Proposal__Account__c, FirstName = names[0], LastName = names[1], Email = signer.dsfs__DocuSign_Recipient_Email__c, Title = signer.dsfs__DocuSign_Recipient_Title__c, sfbase__AuthorityLevel__c = signer.DS_Authority_Level__c);
						newContacts.add(c);
					} 
				}

				if (!newContacts.isEmpty())	{
					insert newContacts;
				}	

				List<dsfs__DocuSign_Recipient_Status__c> signersToBeUpdated = new List<dsfs__DocuSign_Recipient_Status__c> ();
				for(dsfs__DocuSign_Recipient_Status__c signer : completedRecipientsWithNoContactId) {
					for (Contact c : newContacts) {
						if (c.Email == signer.dsfs__DocuSign_Recipient_Email__c && c.AccountId == signer.dsfs__Parent_Status_Record__r.SfdcProposal__r.Apttus_Proposal__Account__c) {
							signer.dsfs__Contact__c = c.Id;
							signersToBeUpdated.add(signer);
							break;
						} 
					}
				}

				if(!signersToBeUpdated.isEmpty()) {
					update signersToBeUpdated;
				}

			}
		}
	}
}