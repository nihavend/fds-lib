package mx.data.events
{
   import flash.events.Event;
   
   [ExcludeClass]
   public class DatabaseUpdateEvent extends Event
   {
      
      public static const UPDATE:String = "update";
      
      public static const INSERT:String = "insert";
      
      public static const DELETE:String = "delete";
       
      
      public var collection:String;
      
      public var key:Object;
      
      public var kind:String;
      
      public function DatabaseUpdateEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = true, collection:String = "", key:Object = null, kind:String = "")
      {
         super(DatabaseUpdateEvent.UPDATE,bubbles,cancelable);
         this.key = key;
         this.kind = kind;
         this.collection = collection;
      }
      
      override public function clone() : Event
      {
         return new DatabaseUpdateEvent(null,false,false,this.collection,this.key,this.kind);
      }
   }
}
