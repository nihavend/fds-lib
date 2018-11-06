package mx.data
{
   import flash.events.IEventDispatcher;
   
   [ExcludeClass]
   public interface IDatabase extends IEventDispatcher
   {
       
      
      function get autoCommit() : Boolean;
      
      function get connected() : Boolean;
      
      function get empty() : Boolean;
      
      function get inTransaction() : Boolean;
      
      function encryptionSupported() : Boolean;
      
      function get encryptLocalCache() : Boolean;
      
      function set encryptLocalCache(param1:Boolean) : void;
      
      function begin(param1:String = null) : void;
      
      function close() : void;
      
      function commit() : void;
      
      function connect(param1:Object) : void;
      
      function drop() : void;
      
      function getCollection(param1:String = "_default_") : IDatabaseCollection;
      
      function rollback() : void;
      
      function getConnection() : Object;
   }
}
