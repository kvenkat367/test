/*
 * RelEng Perforce/RCS Header - Do not remove!
 *
 * $Author: it_promop4 $
 * $Change: 10915343 $
 * $DateTime: 2015/12/01 13:21:51 $
 * $File: //it/applications/org62/C2L/prod/Marketing/src/triggers/spotProfileTrigger.trigger $
 * $Id: //it/applications/org62/C2L/prod/Marketing/src/triggers/spotProfileTrigger.trigger#2 $
 * $Revision: #2 $
 */
 
trigger spotProfileTrigger on Spot_Profile__c bulk (before insert, before update, after insert, after update) {
	
	spotProfileUtil spu = new spotProfileUtil();
	if (Trigger.isBefore) {
		spu.checkProfileFields(Trigger.new);
		if (Trigger.isInsert){
			JigsawSpotProfileUtil jspu = new JigsawSpotProfileUtil();
			jspu.setEmailOptIn(Trigger.new);
		}
	}

	if (Trigger.isAfter && Trigger.isUpdate) {
		spu.updateRecords(Trigger.new, Trigger.oldMap);
	}
}