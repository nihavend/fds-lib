package mx.data
{
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   
   public interface IChangeObject
   {
       
      
      function get changedPropertyNames() : Array;
      
      function get currentVersion() : Object;
      
      function get identity() : Object;
      
      function get message() : DataMessage;
      
      function get newVersion() : Object;
      
      function get previousVersion() : Object;
      
      function getConflict() : DataErrorMessage;
      
      function isCreate() : Boolean;
      
      function isUpdate() : Boolean;
      
      function isDelete() : Boolean;
      
      function conflict(param1:String, param2:Array) : void;
   }
}
