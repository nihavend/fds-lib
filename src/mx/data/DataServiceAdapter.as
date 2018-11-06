package mx.data
{
   import mx.rpc.AsyncRequest;
   
   public class DataServiceAdapter
   {
       
      
      public var dataStore:DataStore;
      
      public function DataServiceAdapter()
      {
         super();
      }
      
      public function get asyncRequest() : AsyncRequest
      {
         return null;
      }
      
      public function get serializeAssociations() : Boolean
      {
         return false;
      }
      
      public function get throwUnhandledFaults() : Boolean
      {
         return true;
      }
      
      public function getDataServiceAdapter(destination:String) : DataServiceAdapter
      {
         var cds:ConcreteDataService = this.dataStore.getDataService(destination);
         if(cds == null)
         {
            return null;
         }
         return cds.adapter;
      }
      
      public function getDataManager(destination:String) : DataManager
      {
         return null;
      }
      
      public function get connected() : Boolean
      {
         return true;
      }
      
      function getConcreteDataService(destination:String) : ConcreteDataService
      {
         var dmgr:DataManager = this.getDataManager(destination);
         if(dmgr != null)
         {
            return dmgr.concreteDataService;
         }
         return null;
      }
   }
}
