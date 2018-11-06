package mx.data.events
{
   import mx.rpc.Fault;
   
   public class UnresolvedConflictsEvent extends DataServiceFaultEvent
   {
      
      public static const FAULT:String = "fault";
       
      
      public function UnresolvedConflictsEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = false)
      {
         super(type,bubbles,cancelable,new Fault("UnresolvedConflict","An attempt was made to commit a transaction with one or more outstanding conflicts."));
      }
   }
}
