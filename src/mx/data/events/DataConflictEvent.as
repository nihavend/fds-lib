package mx.data.events
{
   import flash.events.Event;
   import mx.data.Conflict;
   
   public class DataConflictEvent extends Event
   {
      
      public static const CONFLICT:String = "conflict";
       
      
      private var _conflict:Conflict;
      
      public function DataConflictEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = false, c:Conflict = null)
      {
         super(type,bubbles,cancelable);
         this._conflict = c;
      }
      
      public static function createEvent(c:Conflict) : DataConflictEvent
      {
         return new DataConflictEvent(DataConflictEvent.CONFLICT,false,false,c);
      }
      
      public function get conflict() : Conflict
      {
         return this._conflict;
      }
      
      override public function clone() : Event
      {
         var newEvent:Event = super.clone();
         (newEvent as DataConflictEvent)._conflict = this.conflict;
         return newEvent;
      }
   }
}
