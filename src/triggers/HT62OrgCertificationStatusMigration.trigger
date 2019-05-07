trigger HT62OrgCertificationStatusMigration on HT_Certification_Status__c (before insert, before update, before delete) {
	if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
		Set<Id> existingBadgeAssignmentsIds = new Set<Id>();
		Set<String> certNames = new Set<String>();
		Set<String> dublicatedCertStatuses = new Set<String>();
		Map<String, String> badgeNameCertNameMap = new Map<String, String>();
		Map<String, String> userbadgeidCertStatusMap = new Map<String, String>();
		Map<String, HTSP_Badges_Acquired__c> certStatusbadgeAssignmentsMap = new Map<String, HTSP_Badges_Acquired__c>();
		Map<String, Id> certNameBadgeIdMap = new Map<String, Id>();
		Id badgeAssignmentRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Badges_Acquired' AND SobjectType = 'HTSP_Badges_Acquired__c' LIMIT 1].Id;
		Map<String,String> certStatusUserIdPairMap = HTCertificationStatusTriggerHelper.getCertUserIdPairMap(Trigger.new);
		for (HT_Certification_Status__c certStatusItem : Trigger.new) {
			if (certStatusUserIdPairMap.containsKey(certStatusItem.Name)) {
				certNames.add(certStatusItem.Certification_Type_Name__c);
				if (Trigger.isUpdate && certStatusItem.Badge_Assignment__c != null) {
					existingBadgeAssignmentsIds.add(certStatusItem.Badge_Assignment__c);
				}
			}
		}

		for (HT_S2S_Certification_Badge_Mapping__c mapping : HT_S2S_Certification_Badge_Mapping__c.getall().values()) {
			if (certNames.contains(mapping.Certification_Name__c)) {
				badgeNameCertNameMap.put(mapping.Badge_Name__c, mapping.Certification_Name__c);
			}
		}
		//get badge ids
		for (HTSP_Badge__c badgeItem : [SELECT Id, Name FROM HTSP_Badge__c WHERE Name IN :badgeNameCertNameMap.keySet()]) {
			certNameBadgeIdMap.put(badgeNameCertNameMap.get(badgeItem.Name), badgeItem.Id);
		}

		for (HT_Certification_Status__c certStatusItem : Trigger.new) {
			if (certStatusUserIdPairMap.containsKey(certStatusItem.Name)) {
				Id userId = certStatusUserIdPairMap.get(certStatusItem.Name);
				Id badgeId = certNameBadgeIdMap.get(certStatusItem.Certification_Type_Name__c);
				String userBadge = userId + ':' + badgeId;
				if (userbadgeidCertStatusMap.containsKey(userBadge)) {
					dublicatedCertStatuses.add(certStatusItem.Name);
				} else {
					userbadgeidCertStatusMap.put(userBadge, certStatusItem.Name);
				}
			}
		}

		for (HTSP_Badges_Acquired__c badgeAssignItem : [
			SELECT Id, State__c, Date_Badge_Acquired__c, Badge__c, User__c, User_Badge__c, RecordTypeId, Certification_Status__c
			FROM HTSP_Badges_Acquired__c
			WHERE /*Id IN :existingBadgeAssignmentsIds OR*/ User_Badge__c IN :userbadgeidCertStatusMap.keySet()
		]) {
			certStatusbadgeAssignmentsMap.put(userbadgeidCertStatusMap.get(badgeAssignItem.User_Badge__c), badgeAssignItem);
		}

		Map<String, HTSP_Badges_Acquired__c> badgeAssignmentsForUpsert = new Map<String, HTSP_Badges_Acquired__c>();
		for (HT_Certification_Status__c certStatusItem : Trigger.new) {
			if (!dublicatedCertStatuses.contains(certStatusItem.Name) && certStatusUserIdPairMap.containsKey(certStatusItem.Name) && certNameBadgeIdMap.containsKey(certStatusItem.Certification_Type_Name__c)) {
				HTSP_Badges_Acquired__c badgeAssignment;
				if (certStatusbadgeAssignmentsMap.containsKey(certStatusItem.Name)) {
					badgeAssignment = certStatusbadgeAssignmentsMap.get(certStatusItem.Name);
				} else {
					badgeAssignment = new HTSP_Badges_Acquired__c();
				}
				badgeAssignment.State__c = certStatusItem.Certification_Status__c == 'PARTIALLY_CURRENT'
											|| certStatusItem.Certification_Status__c == 'AT_RISK'
											|| certStatusItem.Certification_Status__c == 'AT_RISK_ANNUAL'
											|| certStatusItem.Certification_Status__c == 'CURRENT' ? 'Acquired' : 'Eligible';
				badgeAssignment.Date_Badge_Acquired__c = certStatusItem.Original_Certification_Date__c;
				badgeAssignment.Badge__c = certNameBadgeIdMap.get(certStatusItem.Certification_Type_Name__c);
				badgeAssignment.User__c = certStatusUserIdPairMap.get(certStatusItem.Name);
				badgeAssignment.RecordTypeId = badgeAssignmentRT;
				badgeAssignment.Certification_Status__c = certStatusItem.Certification_Status__c;
				badgeAssignment.OwnerId = badgeAssignment.User__c;
				badgeAssignmentsForUpsert.put(certStatusItem.Name, badgeAssignment);
			}
		}
		if (!badgeAssignmentsForUpsert.isEmpty()) {
			upsert badgeAssignmentsForUpsert.values();
			for (HT_Certification_Status__c certStatusItem : Trigger.new) {
				if (badgeAssignmentsForUpsert.containsKey(certStatusItem.Name) && certStatusUserIdPairMap.containsKey(certStatusItem.Name)) {
					certStatusItem.Badge_Assignment__c = badgeAssignmentsForUpsert.get(certStatusItem.Name).Id;
				}
			}
		}
	}

	if (Trigger.isBefore && Trigger.isDelete) {
		Set<Id> badgeAssignIds = new Set<Id>();
		//Collect assignments Id
		for (HT_Certification_Status__c aCert : Trigger.old) {
			badgeAssignIds.add(aCert.Badge_Assignment__c);
		}
		
		//Select assignment, based on Set Id
		List<HTSP_Badges_Acquired__c> badgeAssignments = [
															SELECT Id, Badge__c, State__c
															FROM HTSP_Badges_Acquired__c
															WHERE Id IN :badgeAssignIds
																AND State__c = 'Acquired'
		];
		//Change status
		for (HTSP_Badges_Acquired__c badgeAssignment : badgeAssignments) {
			badgeAssignment.State__c = 'Eligible';
		}

		update badgeAssignments;
	}
}