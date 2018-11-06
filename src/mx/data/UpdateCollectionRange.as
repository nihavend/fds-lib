package mx.data
{
   [RemoteClass(alias="flex.data.UpdateCollectionRange")]
   public class UpdateCollectionRange
   {
      
      public static const INSERT_INTO_COLLECTION:int = 0;
      
      public static const DELETE_FROM_COLLECTION:int = 1;
      
      public static const INCREMENT_COLLECTION_SIZE:int = 2;
      
      public static const DECREMENT_COLLECTION_SIZE:int = 3;
      
      public static const UPDATE_COLLECTION_SIZE:int = 4;
       
      
      public var updateType:int;
      
      public var position:int;
      
      public var size:int;
      
      public var identities:Array;
      
      public function UpdateCollectionRange()
      {
         super();
      }
   }
}
