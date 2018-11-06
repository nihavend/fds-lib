package mx.data
{
   [ExcludeClass]
   public interface IDatabaseCursor
   {
       
      
      function get afterLast() : Boolean;
      
      function get beforeFirst() : Boolean;
      
      function get current() : Object;
      
      function moveNext() : void;
      
      function movePrevious() : void;
      
      function seek(param1:int, param2:int = -1, param3:int = 0) : void;
   }
}
