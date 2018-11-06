package mx.data
{
   import mx.utils.ArrayUtil;
   
   public class PropertySpecifier
   {
      
      public static const INCLUDE_DEFAULT:int = 0;
      
      public static const INCLUDE_ALL:int = 1;
      
      public static const INCLUDE_DEFAULT_PLUS_LIST:int = 2;
      
      public static const INCLUDE_LIST:int = 3;
      
      public static const DEFAULT:PropertySpecifier = new PropertySpecifier(null,INCLUDE_DEFAULT,null);
      
      public static const ALL:PropertySpecifier = new PropertySpecifier(null,INCLUDE_ALL,null);
      
      public static const EMPTY:PropertySpecifier = new PropertySpecifier(null,INCLUDE_LIST,[]);
       
      
      private var _destination:ConcreteDataService;
      
      private var _includeMode:int = 0;
      
      private var _extraProperties:Array = null;
      
      public function PropertySpecifier(dest:ConcreteDataService, mode:int, extra:Array)
      {
         super();
         this._destination = dest;
         this._includeMode = mode;
         this._extraProperties = extra;
      }
      
      static function getPropertySpecifier(dest:ConcreteDataService, properties:Array, includeDefault:Boolean = true) : PropertySpecifier
      {
         return new PropertySpecifier(dest,!!includeDefault?int(INCLUDE_DEFAULT_PLUS_LIST):int(INCLUDE_LIST),properties);
      }
      
      public function get includeMode() : int
      {
         return this._includeMode;
      }
      
      public function set includeMode(fm:int) : void
      {
         this._includeMode = fm;
      }
      
      public function get excludes() : Array
      {
         if(this._destination == null)
         {
            return null;
         }
         if(this._includeMode == INCLUDE_DEFAULT)
         {
            return this._destination.metadata.loadOnDemandProperties;
         }
         if(this._includeMode == INCLUDE_ALL)
         {
            return null;
         }
         var toReturn:Array = [];
         return this.intersectLists(toReturn,this.includeMode == INCLUDE_LIST?this._destination.metadata.propertyNames:this._destination.metadata.loadOnDemandProperties,this._extraProperties);
      }
      
      private function intersectLists(result:Array, l1:Array, l2:Array) : Array
      {
         var s:String = null;
         for(var i:int = 0; i < l1.length; i++)
         {
            s = l1[i].toString();
            if(ArrayUtil.getItemIndex(s,l2) == -1)
            {
               result.push(s);
            }
         }
         return result;
      }
      
      public function includeProperty(propName:String) : Boolean
      {
         if(this._destination == null)
         {
            return true;
         }
         if(this._includeMode == INCLUDE_ALL)
         {
            return true;
         }
         if(this._includeMode == INCLUDE_DEFAULT)
         {
            return this._destination.metadata.isDefaultProperty(propName);
         }
         if(this._includeMode == INCLUDE_DEFAULT_PLUS_LIST && this._destination.metadata.isDefaultProperty(propName))
         {
            return true;
         }
         if(ArrayUtil.getItemIndex(propName,this._extraProperties) != -1)
         {
            return true;
         }
         return false;
      }
      
      public function getSubSpecifier(item:Object, propName:String) : PropertySpecifier
      {
         if(this._destination == null)
         {
            return DEFAULT;
         }
         var itemDest:ConcreteDataService = this._destination.getItemDestination(item);
         var assoc:ManagedAssociation = itemDest.metadata.associations[propName];
         if(assoc == null)
         {
            return DEFAULT;
         }
         var subDest:ConcreteDataService = itemDest.dataStore.getDataService(assoc.destination);
         if(this.includeMode == INCLUDE_ALL)
         {
            return subDest.includeAllSpecifier;
         }
         return subDest.includeDefaultSpecifier;
      }
      
      function getSubclassSpecifier(extDS:ConcreteDataService) : PropertySpecifier
      {
         if(this._includeMode == INCLUDE_DEFAULT)
         {
            return extDS.includeDefaultSpecifier;
         }
         if(this._includeMode == INCLUDE_ALL)
         {
            return extDS.includeAllSpecifier;
         }
         if(this._includeMode == INCLUDE_LIST)
         {
            return getPropertySpecifier(extDS,this._extraProperties,false);
         }
         return getPropertySpecifier(extDS,this._extraProperties,true);
      }
      
      public function set extraProperties(props:Array) : void
      {
         this._extraProperties = props;
      }
      
      public function get extraProperties() : Array
      {
         return this._extraProperties;
      }
      
      public function getExcluded(item:Object) : Array
      {
         if(this.includeMode == INCLUDE_ALL)
         {
            return null;
         }
         if(this.includeMode == INCLUDE_DEFAULT)
         {
            return this._destination.metadata.loadOnDemandProperties;
         }
         if(this.includeMode == INCLUDE_DEFAULT_PLUS_LIST)
         {
            return this.excludes;
         }
         if(this._destination.metadata.itemClass != null)
         {
            return this.intersectLists(new Array(),ConcreteDataService.getObjectProperties(item),this._extraProperties);
         }
         return this.intersectLists(new Array(),this._destination.metadata.propertyNames,this._extraProperties);
      }
      
      public function getIncluded(destination:String) : Array
      {
         var props:Array = null;
         var propName:String = null;
         var i:int = 0;
         var cds:ConcreteDataService = ConcreteDataService.lookupService(destination);
         var propList:Array = [];
         if(this.includeMode == INCLUDE_ALL)
         {
            propList = cds.metadata.propertyNames;
         }
         if(this.includeMode == INCLUDE_LIST)
         {
            propList = this.extraProperties;
         }
         if(this.includeMode == INCLUDE_DEFAULT)
         {
            props = cds.metadata.propertyNames;
            for(i = 0; i < props.length; i++)
            {
               propName = props[i];
               if(cds.metadata.isNonAssociatedProperty(propName))
               {
                  propList.push(propName);
               }
            }
         }
         return propList;
      }
      
      public function get includeSpecifierString() : String
      {
         var str:String = null;
         var i:int = 0;
         if(this.includeMode == INCLUDE_ALL)
         {
            return "*";
         }
         if(this.includeMode == INCLUDE_DEFAULT)
         {
            return null;
         }
         if(this.includeMode == INCLUDE_DEFAULT_PLUS_LIST)
         {
            str = "+";
         }
         else
         {
            str = "";
         }
         if(this._extraProperties != null)
         {
            for(i = 0; i < this._extraProperties.length; i++)
            {
               if(i != 0)
               {
                  str = str + ",";
               }
               str = str + this._extraProperties[i];
            }
         }
         return str;
      }
      
      public function toString() : String
      {
         if(this._includeMode == INCLUDE_DEFAULT)
         {
            if(this._destination == null)
            {
               return "(include default - no destination)";
            }
            return "(include default - excludes: " + ConcreteDataService.itemToString(this.excludes) + ")";
         }
         if(this._includeMode == INCLUDE_ALL)
         {
            return "(include all)";
         }
         return "include properties " + ConcreteDataService.itemToString(this._extraProperties);
      }
   }
}
