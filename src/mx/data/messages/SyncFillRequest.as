package mx.data.messages
{
   [RemoteClass(alias="flex.data.messages.SyncFillRequest")]
   public class SyncFillRequest
   {
       
      
      public var sinceTimestamp:Date;
      
      public var fillParameters:Array;
      
      public function SyncFillRequest()
      {
         super();
      }
   }
}
