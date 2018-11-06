package mx.data
{
   import flash.events.IEventDispatcher;
   
   [ExcludeClass]
   public interface IDatabaseCollection extends IEventDispatcher
   {
       
      
      function createCursor() : IDatabaseCursor;
      
      function count() : void;
      
      function drop() : void;
      
      function get(param1:Object) : Object;
      
      function put(param1:Object, param2:Object) : void;
      
      function remove(param1:Object) : void;
      
      function removeAll() : void;
   }
}
