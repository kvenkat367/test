/*
* RelEng Perforce/RCS Header - Do not remove!
*
* $Author:  $
* $Change:  $
* $DateTime: $
* $File:  $
* $Id:  $
* $Revision:  $
*/
/*
* Implementaion:
* Batch to create Employee Model records from Model and Employee records
* Called from:
* 1. Model Trigger --> ModelObjectService --> Schedule BatchCreateEmployeeForModel ( no model id will be passed in this case )
* 2. BatchSchedulePage --> Chained process section --> BatchCreateEmployeeForModel ( model id will be passed )
* @author archita
* @modified by sbiswas@salesforce.com
*/
global class  BatchCreateEmployeeForModel implements  Database.Batchable<sObject>,Schedulable{
    
    /* Static variables to track the status of the model batch jobs */
    public static String CURRENT_MODEL_SETUP_STATUS ='New';
    public static String NEW_MODEL_SETUP_STATUS ='Establish Manager';
    // Get the batch size defined in custom setting
    public static Integer BATCH_SIZE = CustomSettingsService.getBatchSize( 'BatchCreateEmployeeForModel' );
    /* Storing the Model id, so that it can be passed in the constructor of the class from caller method */
    public String modelID;
    public String modelType;
    
    /*
    * parametrized constructor for passing the model id for which the batch job will run
    * @param modelId - model id for which the batch jobs will run
    * @param modelType - model type... Planning Model - Employee Models created for Employee with IsCommissionable flag true
    * ... and in Operation model, for all Employee's, Employee Models are created
    */
    global  BatchCreateEmployeeForModel( String modelId, String modelType ){
        this.modelID = modelId;
        this.modelType = modelType; 
    }
    /*
    * start method which will generate the scope of the batch job ( records for Employee )
    */
    global Database.Querylocator start( Database.BatchableContext BC ) {       
        return Database.getQueryLocator( 'Select Id, Employee_Id__c, Cost_Center__c, IsCommissionable__c, ' + 
                                                                       ' Management_Chain_Employee_ID_String__c from Employee__c' );
    }
    /*
    * implements the execute for the Schedular
    * called from trigger of Model ( ModelObjectService ) ONLY, since this is the starting point. There will be no model id passed from trigger of model
    */
    global void execute( SchedulableContext sc ) {
        BatchCreateEmployeeForModel batch = new BatchCreateEmployeeForModel( this.modelId, this.modelType );
        ID batchprocessid = Database.executeBatch( batch, BATCH_SIZE );
    }
    /*
    * actual execute method. called from above execute method
    * @param empRecs - List of Employee Records
    * @param BC - batchable context passed from start method
    */
    global void execute( Database.BatchableContext BC, List<Employee__c> empRecs ) {
        EmployeeFilterUtility empFilterUtil = new EmployeeFilterUtility( modelType );    
        Map<Id,Employee__c> empRecMap = new Map<Id,Employee__c>( empFilterUtil.getEmployeeRecords( empRecs ) ); 
        Set<Id> validCCEmpIds = empRecMap.keySet();
        if( !empRecMap.isEmpty() ){
            List<Employee__c> validCCEmps = new List<Employee__c>();
            List<String> fieldList = new List<String> ();
            for(String  field : Constants.employeeFieldMapCS.keySet()) {   
                fieldList.add(field);
            }
            String queryString = SOQLUtil.querySObject(Constants.employeeObjectName,fieldList);
            queryString = queryString + ' where Id in :validCCEmpIds';
            validCCEmps = Database.query( queryString );
            // populating the model ids in a set
            List<Id> modelIds = new List<Id>();
            modelIds.add( modelId );
            // create the EmployeeModel
            List<Employee_Model__c> empModels = EmployeeModelUtility.createEmployeeModelRecords( validCCEmps, modelIds );
            List<Database.UpsertResult> upsertResult = Database.upsert( empModels, Employee_Model__c.Fields.ModelEmpIdKey__c, false );
            //log the error from the upsert operation if any 
            List<String> fieldLs = new List<String>();
            fieldLs.add('Model__c');
            fieldLs.add('Employee_Id__c');
            SPMDebugService.processDatabaseUpsertErrors(upsertResult, empModels, 'ModelEmpIdKey__c', fieldLs, 'BatchCreateEmployeeForModel','ERROR on upsert of Employee Model Records:');        
        }
    }
    /*
    * finish method will run at the end of all batch jobs. we are chaining batch jobs here
    */
    global void finish( Database.BatchableContext BC ){
        //TODO : Code to do Batch failure  monitoring . Send notification emails on batch failure.Or we can have an object where failue can be logged.        
        ModelUtility.updateModelSetupStatus( CURRENT_MODEL_SETUP_STATUS,NEW_MODEL_SETUP_STATUS,modelID );
        //TODO: mailing mechanism to monitor batch failures.
        //Schedule the batch to Establish the manager Link
       //Build the system time of now + 20 seconds to schedule the batch apex.
        Datetime sysTime = System.now();
        sysTime = sysTime.addSeconds(20);
        String chronExp = '' + sysTime.second() + ' ' + sysTime.minute() + ' ' + sysTime.hour() + ' ' + sysTime.day() + ' ' + sysTime.month() + ' ? ' + sysTime.year();        
        // Schedule the next job, i.e. the manager establish  batch
        // called from BatchSchedularPage --> chained batch job section
        System.schedule( 'BatchEstablishManager' + sysTime.getTime(),chronExp, new BatchEstablishManager( this.modelID, true ) );
    }
}
