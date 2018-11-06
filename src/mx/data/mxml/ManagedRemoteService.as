package mx.data.mxml
{
   import mx.core.IMXMLObject;
   
   public dynamic class ManagedRemoteService extends mx.data.ManagedRemoteService implements IMXMLObject
   {
       
      
      var document:Object;
      
      var id:String;
      
      public function ManagedRemoteService(dest:String = null)
      {
         super(dest);
      }
      
      public function initialized(document:Object, id:String) : void
      {
         this.document = document;
         this.id = id;
         initialize();
      }
   }
}
