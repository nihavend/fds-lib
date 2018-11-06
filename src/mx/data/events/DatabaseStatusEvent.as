package mx.data.events
{
   import flash.events.Event;
   import flash.events.StatusEvent;
   
   [ExcludeClass]
   public class DatabaseStatusEvent extends StatusEvent
   {
      
      public static const STATUS:String = "status";
       
      
      public var details:String;
      
      public function DatabaseStatusEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = true, code:String = "", level:String = "", details:String = "")
      {
         super(DatabaseStatusEvent.STATUS,bubbles,cancelable,code,level);
         this.details = details;
      }
      
      override public function clone() : Event
      {
         return new DatabaseStatusEvent(null,false,false,code,level,this.details);
      }
   }
}
