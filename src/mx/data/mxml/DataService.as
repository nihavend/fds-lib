package mx.data.mxml
{
   import mx.core.IMXMLObject;
   import mx.data.ConcreteDataService;
   
   public class DataService extends mx.data.DataService implements IMXMLObject
   {
       
      
      var document:Object;
      
      var id:String;
      
      public function DataService(dest:String = null)
      {
         super(dest);
      }
      
      public function initialized(document:Object, id:String) : void
      {
         this.document = document;
         this.id = id;
      }
      
      override public function get destination() : String
      {
         if(_implementation != null)
         {
            return super.destination;
         }
         return Boolean(propertyCache.destination)?propertyCache.destination:null;
      }
      
      public function set destination(dest:String) : void
      {
         setImplementation(ConcreteDataService.getService(dest));
      }
   }
}
