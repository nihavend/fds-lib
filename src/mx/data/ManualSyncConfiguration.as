package mx.data
{
   import mx.collections.ArrayCollection;
   
   public class ManualSyncConfiguration
   {
       
      
      var dataService:ConcreteDataService;
      
      public var producerDefaultHeaders:Object;
      
      public var producerSubtopics:ArrayCollection;
      
      public function ManualSyncConfiguration()
      {
         this.producerSubtopics = new ArrayCollection();
         super();
      }
      
      public function set consumerSubscriptions(s:ArrayCollection) : void
      {
         this.checkInitialization();
         this.dataService.consumer.subscriptions = s;
      }
      
      public function get consumerSubscriptions() : ArrayCollection
      {
         return this.dataService.consumer.subscriptions;
      }
      
      public function consumerAddSubscription(subtopic:String = null, selector:String = null, maxFrequency:uint = 0) : void
      {
         this.dataService.consumer.addSubscription(subtopic,selector,maxFrequency);
      }
      
      public function consumerRemoveSubscription(subtopic:String = null, selector:String = null) : void
      {
         this.dataService.consumer.removeSubscription(subtopic,selector);
      }
      
      public function consumerSubscribe(clientId:String = null) : void
      {
         this.checkInitialization();
         this.dataService.manualSubscribe(clientId);
      }
      
      public function consumerUnsubscribe() : void
      {
         this.checkInitialization();
         this.dataService.manualUnsubscribe();
      }
      
      private function checkInitialization() : void
      {
         if(!this.dataService.initialized)
         {
            this.dataService.dataStore.initialize(null,null);
         }
      }
   }
}
