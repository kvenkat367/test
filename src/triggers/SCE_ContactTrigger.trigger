/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: egoldman $
 * $Change:  $
 * $DateTime:  $
 * $File:  $
 * $Id:  $
 * $Revision: $
 */

trigger SCE_ContactTrigger on Contact (before insert, before update, after insert, after update) {

	if(Trigger.isBefore){
		SCE_ContactTriggerHandler.processNoLongerWithCompany(Trigger.old, Trigger.new);
	}

	if(Trigger.isAfter){
		//Process Contacts for DC's
		SCE_ContactTriggerHandler.processContactsForDCs(trigger.new, trigger.oldMap);
	}
}