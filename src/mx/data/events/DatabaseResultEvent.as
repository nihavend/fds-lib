package mx.data.events
{
   import flash.events.Event;
   
   [ExcludeClass]
   public class DatabaseResultEvent extends Event
   {
      
      public static const RESULT:String = "result";
       
      
      public var result:Object;
      
      public var changeCount:uint;
      
      public function DatabaseResultEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = true, result:Object = null, changeCount:uint = 0)
      {
         super(DatabaseResultEvent.RESULT,bubbles,cancelable);
         this.result = result;
         this.changeCount = changeCount;
      }
      
      override public function clone() : Event
      {
         return new DatabaseResultEvent(null,false,false,this.result,this.changeCount);
      }
   }
}
