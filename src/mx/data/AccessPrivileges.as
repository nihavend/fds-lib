package mx.data
{
   public class AccessPrivileges
   {
      
      public static const NONE:uint = 0;
      
      public static const ADD:uint = 2;
      
      public static const UPDATE:uint = 4;
      
      public static const REMOVE:uint = 8;
      
      public static const ALL:uint = 14;
       
      
      private var _privileges:uint;
      
      public function AccessPrivileges(privileges:uint = 14)
      {
         super();
         this._privileges = privileges;
      }
      
      public function get canUpdate() : Boolean
      {
         return (this._privileges & AccessPrivileges.UPDATE) == AccessPrivileges.UPDATE;
      }
      
      public function get canRemove() : Boolean
      {
         return (this._privileges & AccessPrivileges.REMOVE) == AccessPrivileges.REMOVE;
      }
      
      public function get canAdd() : Boolean
      {
         return (this._privileges & AccessPrivileges.ADD) == AccessPrivileges.ADD;
      }
      
      public function get canModify() : Boolean
      {
         return this._privileges != 0;
      }
   }
}
