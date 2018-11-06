package mx.data
{
   import mx.collections.ArrayCollection;
   import mx.collections.ListCollectionView;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   
   [ResourceBundle("data")]
   public class ManagedQuery extends ManagedOperation
   {
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      public var countOperation:String;
      
      public var synchronizeOperation:String;
      
      public var pagingEnabled:Boolean;
      
      public var positionalPagingParameters:Boolean = false;
      
      public var addItemToCollectionOperation:String;
      
      public var removeItemFromCollectionOperation:String;
      
      private var _propertySpecifier:String;
      
      private var _includeSpecifier:PropertySpecifier;
      
      private var _pageSize:int = 0;
      
      var startIndexParamPos:int = -1;
      
      var numItemsParamPos:int = -1;
      
      public function ManagedQuery(nameParam:String = null, typeParam:String = "query")
      {
         super(nameParam,typeParam);
      }
      
      public function get propertySpecifier() : String
      {
         return this._propertySpecifier;
      }
      
      public function set propertySpecifier(ps:String) : void
      {
         this._propertySpecifier = ps;
         this._includeSpecifier = null;
      }
      
      public function set pageSize(ps:int) : void
      {
         this._pageSize = ps;
      }
      
      public function get pageSize() : int
      {
         if(this._pageSize == 0)
         {
            return dataManager.pageSize;
         }
         return this._pageSize;
      }
      
      function get pageSizeSet() : Boolean
      {
         return this._pageSize != 0;
      }
      
      function get includeSpecifier() : PropertySpecifier
      {
         if(this._includeSpecifier == null && this._propertySpecifier != null)
         {
            this._includeSpecifier = dataManager.concreteDataService.parsePropertySpecifierString(this._propertySpecifier);
         }
         return this._includeSpecifier;
      }
      
      override public function initialize() : void
      {
         var error:Boolean = false;
         var i:int = 0;
         var param:String = null;
         super.initialize();
         if(this.countOperation != null && dataManager.service.getOperation(this.countOperation) == null)
         {
            throw new ArgumentError(resourceManager.getString("data","countOperationNotFoundInService",[name,this.countOperation]));
         }
         if(this.addItemToCollectionOperation != null && dataManager.service.getOperation(this.addItemToCollectionOperation) == null)
         {
            throw new ArgumentError(resourceManager.getString("data","addItemToCollectionOperationNotFoundInService",[name,this.addItemToCollectionOperation]));
         }
         if(this.removeItemFromCollectionOperation != null && dataManager.service.getOperation(this.removeItemFromCollectionOperation) == null)
         {
            throw new ArgumentError(resourceManager.getString("data","removeItemFromCollectionNotFoundInService",[name,this.removeItemFromCollectionOperation]));
         }
         if(this.synchronizeOperation && dataManager.service.getOperation(this.synchronizeOperation) == null)
         {
            throw new ArgumentError(resourceManager.getString("data","synchronizeOperationNotFoundInService",[name,this.synchronizeOperation]));
         }
         if(this.pagingEnabled)
         {
            if(resultType != null && resultType != ArrayCollection && resultType != ListCollectionView)
            {
               throw new ArgumentError(resourceManager.getString("data","pagingEnabledResultNotCollection",[name]));
            }
            if(parameters != null)
            {
               if(this.positionalPagingParameters)
               {
                  error = false;
                  if(parametersArray.length < 2)
                  {
                     throw new ArgumentError(resourceManager.getString("data","pagingQueryPositionalParametersLength",[name,dataManager.destination]));
                  }
                  this.startIndexParamPos = parametersArray.length - 2;
                  this.numItemsParamPos = parametersArray.length - 1;
               }
               else
               {
                  for(i = 0; i < parametersArray.length; i++)
                  {
                     param = parametersArray[i];
                     if(param == "startIndex")
                     {
                        this.startIndexParamPos = i;
                     }
                     else if(param == "numItems")
                     {
                        this.numItemsParamPos = i;
                     }
                  }
                  if(this.startIndexParamPos == -1 || this.numItemsParamPos == -1)
                  {
                     throw new ArgumentError(resourceManager.getString("data","pagingQueryNeedsIndexParameters",[name,dataManager.destination]));
                  }
               }
            }
         }
      }
   }
}
