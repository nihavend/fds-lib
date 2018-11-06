package mx.data.messages
{
   import mx.data.RemoveFromFillConflictDetails;
   import mx.messaging.messages.ErrorMessage;
   
   [RemoteClass(alias="flex.data.messages.DataErrorMessage")]
   public class DataErrorMessage extends ErrorMessage
   {
       
      
      public var cause:DataMessage;
      
      public var propertyNames:Array;
      
      public var serverObject:Object;
      
      public var removeFromFillConflictDetails:RemoveFromFillConflictDetails;
      
      public function DataErrorMessage()
      {
         super();
      }
   }
}
