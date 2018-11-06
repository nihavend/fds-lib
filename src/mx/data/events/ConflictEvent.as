package mx.data.events
{
   import mx.data.messages.DataErrorMessage;
   import mx.messaging.events.MessageEvent;
   
   [ExcludeClass]
   public class ConflictEvent extends MessageEvent
   {
      
      public static const CONFLICT:String = "conflict";
       
      
      public function ConflictEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = false, msg:DataErrorMessage = null)
      {
         super(type,bubbles,cancelable,msg);
      }
      
      public static function createEvent(msg:DataErrorMessage) : ConflictEvent
      {
         return new ConflictEvent(ConflictEvent.CONFLICT,false,false,msg);
      }
   }
}
