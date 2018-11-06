package mx.data
{
   import flash.events.IEventDispatcher;
   
   public interface IITemReference extends IEventDispatcher
   {
       
      
      [Bindable(event="propertyChange")]
      function get valid() : Boolean;
      
      function set valid(param1:Boolean) : void;
      
      function releaseItem(param1:Boolean = true, param2:Boolean = true) : void;
   }
}
