package mx.data.utils
{
   import flash.events.IEventDispatcher;
   import flash.utils.ByteArray;
   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;
   import flash.xml.XMLNode;
   import mx.collections.ArrayList;
   import mx.collections.IList;
   import mx.collections.ListCollectionView;
   import mx.data.ConcreteDataService;
   import mx.data.DataList;
   import mx.data.IManaged;
   import mx.data.ManagedAssociation;
   import mx.data.ManagedObjectProxy;
   import mx.data.errors.DataServiceError;
   import mx.events.PropertyChangeEvent;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.utils.ObjectProxy;
   import mx.utils.ObjectUtil;
   
   [ResourceBundle("data")]
   public class Managed
   {
      
      public static const UNSET_PROPERTY:String = "__UNSET__";
      
      private static var refCount:int = 0;
      
      static const LISTENER_TABLE_KEY:String = "_LT::";
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      public function Managed()
      {
         super();
      }
      
      public static function createUpdateEvent(obj:IManaged, property:Object, event:PropertyChangeEvent) : PropertyChangeEvent
      {
         var objEvent:PropertyChangeEvent = null;
         if(event.target is IEventDispatcher)
         {
            if(property != null)
            {
               objEvent = PropertyChangeEvent(event.clone());
               objEvent.property = property + "." + event.property;
               return objEvent;
            }
         }
         return event;
      }
      
      public static function getProperty(obj:IManaged, property:String, value:*, useHierarchicalValues:Boolean = true) : *
      {
         var destination:String = null;
         var parentService:ConcreteDataService = null;
         var assoc:ManagedAssociation = null;
         var referencedIds:Object = null;
         var isEventDispatcher:Boolean = false;
         var savedValue:* = undefined;
         var isListCollectionView:Boolean = false;
         var listenerTable:Object = null;
         var f:Function = null;
         var propReferencedIds:Object = null;
         referencedIds = (obj as Object).referencedIds;
         if(referencedIds != null && (propReferencedIds = referencedIds[property]) == UNSET_PROPERTY)
         {
            destination = getDestination(obj);
            if(destination != null && destination != "" && obj is IManaged)
            {
               parentService = ConcreteDataService.getService(destination);
               parentService.fetchItemProperty(IManaged(obj),property);
            }
         }
         if(value === null || value === undefined)
         {
            destination = getDestination(obj);
            if(destination != null && destination != "")
            {
               parentService = ConcreteDataService.getService(destination);
               assoc = parentService.metadata.associations[property];
               if(assoc != null && assoc.typeCode == ManagedAssociation.ONE)
               {
                  if(assoc.loadOnDemand || propReferencedIds != null)
                  {
                     value = parentService.resolveReference(obj,assoc);
                  }
               }
            }
         }
         else if(useHierarchicalValues)
         {
            isEventDispatcher = value is IEventDispatcher;
            if(isEventDispatcher || value.constructor == Object)
            {
               savedValue = value;
               isListCollectionView = false;
               if(isEventDispatcher)
               {
                  if(value is ListCollectionView)
                  {
                     isListCollectionView = true;
                     value = ListCollectionView(value).list;
                  }
               }
               else
               {
                  value = new ManagedObjectProxy(value);
               }
               destination = getDestination(obj);
               if(destination != null)
               {
                  parentService = ConcreteDataService.getService(destination);
                  assoc = parentService.getItemMetadata(obj).associations[property];
                  if(assoc != null)
                  {
                     if(isListCollectionView)
                     {
                        value = savedValue;
                     }
                     return value;
                  }
               }
               referencedIds = getReferencedIds(obj);
               if(referencedIds == null)
               {
                  setReferencedIds(obj,referencedIds = new Object());
               }
               listenerTable = referencedIds[Managed.LISTENER_TABLE_KEY];
               if(listenerTable == null)
               {
                  listenerTable = new Object();
                  referencedIds[Managed.LISTENER_TABLE_KEY] = listenerTable;
               }
               if(listenerTable[property] == null)
               {
                  f = createSubPropertyChangeHandler(obj,property);
                  listenerTable[property] = f;
                  value.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,f);
                  if(value is ArrayList)
                  {
                     Managed.normalizeValues(ArrayList(value));
                     value = savedValue;
                  }
               }
               if(isListCollectionView)
               {
                  value = savedValue;
               }
            }
         }
         return value;
      }
      
      public static function getReferencedIds(obj:Object) : Object
      {
         var rids:Object = null;
         try
         {
            rids = obj.referencedIds;
            if(rids == null)
            {
               setReferencedIds(obj,rids = new Object());
            }
            return rids;
         }
         catch(re:ReferenceError)
         {
            throw new DataServiceError(resourceManager.getString("data","missingReferencedIdProperty",[ObjectUtil.getClassInfo(obj).name]));
         }
         return null;
      }
      
      public static function setReferencedIds(obj:Object, ids:Object) : void
      {
         var oldRefIds:Object = null;
         var listenerTable:Object = null;
         try
         {
            oldRefIds = obj.referencedIds;
            obj.referencedIds = ids;
            if(oldRefIds != null)
            {
               listenerTable = oldRefIds[LISTENER_TABLE_KEY];
               if(listenerTable != null && ids != null)
               {
                  ids[LISTENER_TABLE_KEY] = listenerTable;
               }
            }
         }
         catch(re:ReferenceError)
         {
            throw new DataServiceError(resourceManager.getString("data","missingReferencedIdProperty",[ObjectUtil.getClassInfo(obj).name]));
         }
      }
      
      public static function getDestination(obj:Object) : String
      {
         try
         {
            return obj.destination;
         }
         catch(re:ReferenceError)
         {
            throw new DataServiceError(resourceManager.getString("data","missingDestinationProperty",[ObjectUtil.getClassInfo(obj).name]));
         }
         return null;
      }
      
      public static function setDestination(obj:Object, destination:String) : void
      {
         try
         {
            obj.destination = destination;
         }
         catch(re:ReferenceError)
         {
            throw new DataServiceError(resourceManager.getString("data","missingDestinationProperty",[ObjectUtil.getClassInfo(obj).name]));
         }
      }
      
      public static function normalizeValues(value:ArrayList) : void
      {
         var item:* = undefined;
         var i:uint = 0;
         var items:Array = value.source;
         if(items.length > 0)
         {
            item = items[0];
            if(item === null || item is IManaged || item is ListCollectionView || item.constructor != Object)
            {
               return;
            }
            for(i = 0; i < items.length; i++)
            {
               items[i] = normalize(items[i]);
            }
            value.source = items;
         }
      }
      
      public static function normalize(value:*) : *
      {
         if(value !== undefined && value !== null && !(value is IManaged) && value.constructor == Object)
         {
            value = new ManagedObjectProxy(value);
         }
         return value;
      }
      
      public static function setProperty(obj:IManaged, property:Object, oldValue:*, newValue:*) : void
      {
         var propValue:* = undefined;
         var referencedIds:Object = null;
         var propStr:String = null;
         var listenerTable:Object = null;
         var entry:Object = null;
         if(oldValue !== newValue)
         {
            propValue = oldValue;
            if(propValue is ListCollectionView)
            {
               propValue = ListCollectionView(propValue).list;
            }
            if(propValue is IEventDispatcher)
            {
               referencedIds = getReferencedIds(obj);
               propStr = property.toString();
               if(referencedIds != null)
               {
                  listenerTable = referencedIds[LISTENER_TABLE_KEY];
                  if(listenerTable != null)
                  {
                     entry = listenerTable[propStr];
                     if(entry != null)
                     {
                        propValue.removeEventListener(PropertyChangeEvent.PROPERTY_CHANGE,entry);
                     }
                     listenerTable[propStr] = null;
                  }
               }
            }
            if(obj.hasEventListener(PropertyChangeEvent.PROPERTY_CHANGE))
            {
               obj.dispatchEvent(PropertyChangeEvent.createUpdateEvent(obj,property,oldValue,newValue));
            }
         }
      }
      
      public static function propertyFetched(obj:Object, property:String) : Boolean
      {
         var referencedIds:Object = null;
         try
         {
            referencedIds = obj.referencedIds;
            return referencedIds == null || referencedIds[property] != UNSET_PROPERTY;
         }
         catch(re:ReferenceError)
         {
         }
         return true;
      }
      
      static function compare(a:Object, b:Object, depth:int = -1, excludes:Array = null) : int
      {
         return internalCompare(a,b,0,depth,new Dictionary(true),excludes);
      }
      
      private static function internalCompare(a:Object, b:Object, currentDepth:int, desiredDepth:int, refs:Dictionary, excludes:Array) : int
      {
         var newDepth:int = 0;
         var aRef:Boolean = false;
         var bRef:Boolean = false;
         var aProps:Array = null;
         var bProps:Array = null;
         var propName:QName = null;
         var aProp:Object = null;
         var bProp:Object = null;
         var i:int = 0;
         if(a == null && b == null)
         {
            return 0;
         }
         if(a == null)
         {
            return 1;
         }
         if(b == null)
         {
            return -1;
         }
         if(a is ObjectProxy)
         {
            a = ObjectProxy(a).object;
         }
         if(b is ObjectProxy)
         {
            b = ObjectProxy(b).object;
         }
         var typeOfA:String = typeof a;
         var typeOfB:String = typeof b;
         var result:int = 0;
         if(typeOfA == typeOfB)
         {
            switch(typeOfA)
            {
               case "boolean":
                  result = ObjectUtil.numericCompare(Number(a),Number(b));
                  break;
               case "number":
                  result = ObjectUtil.numericCompare(a as Number,b as Number);
                  break;
               case "string":
                  result = ObjectUtil.stringCompare(a as String,b as String);
                  break;
               case "xml":
                  result = ObjectUtil.stringCompare((a as XML).toXMLString(),(b as XML).toXMLString());
                  break;
               case "object":
                  newDepth = desiredDepth > 0?int(desiredDepth - 1):int(desiredDepth);
                  aRef = refs[a];
                  bRef = refs[b];
                  if(aRef && !bRef)
                  {
                     return 1;
                  }
                  if(bRef && !aRef)
                  {
                     return -1;
                  }
                  if(bRef && aRef)
                  {
                     return 0;
                  }
                  refs[a] = true;
                  refs[b] = true;
                  if(desiredDepth != -1 && currentDepth > desiredDepth)
                  {
                     result = ObjectUtil.stringCompare(a.toString(),b.toString());
                  }
                  else if(a is Array && b is Array)
                  {
                     result = arrayCompare(a as Array,b as Array,currentDepth,desiredDepth,refs,excludes);
                  }
                  else if(a is Date && b is Date)
                  {
                     result = ObjectUtil.dateCompare(a as Date,b as Date);
                  }
                  else if(a is IList && b is IList)
                  {
                     result = listCompare(a as IList,b as IList,currentDepth,desiredDepth,refs,excludes);
                  }
                  else if(a is ByteArray && b is ByteArray)
                  {
                     result = byteArrayCompare(a as ByteArray,b as ByteArray);
                  }
                  else if(getQualifiedClassName(a) == getQualifiedClassName(b))
                  {
                     aProps = ObjectUtil.getClassInfo(a,excludes).properties;
                     if(getQualifiedClassName(a) == "Object")
                     {
                        bProps = ObjectUtil.getClassInfo(b,excludes).properties;
                        result = arrayCompare(aProps,bProps,currentDepth,newDepth,refs,excludes);
                     }
                     if(result != 0)
                     {
                        return result;
                     }
                     for(i = 0; i < aProps.length; i++)
                     {
                        propName = aProps[i];
                        aProp = a[propName];
                        bProp = b[propName];
                        result = internalCompare(aProp,bProp,currentDepth + 1,newDepth,refs,excludes);
                        if(result != 0)
                        {
                           i = aProps.length;
                        }
                     }
                  }
                  else
                  {
                     return 1;
                  }
                  break;
            }
            return result;
         }
         return ObjectUtil.stringCompare(typeOfA,typeOfB);
      }
      
      private static function arrayCompare(a:Array, b:Array, currentDepth:int, desiredDepth:int, refs:Dictionary, excludes:Array) : int
      {
         var key:* = null;
         var result:int = 0;
         if(a.length != b.length)
         {
            if(a.length < b.length)
            {
               result = -1;
            }
            else
            {
               result = 1;
            }
         }
         else
         {
            for(key in a)
            {
               if(!b.hasOwnProperty(key))
               {
                  return -1;
               }
               result = internalCompare(a[key],b[key],currentDepth,desiredDepth,refs,excludes);
               if(result != 0)
               {
                  return result;
               }
            }
            for(key in b)
            {
               if(!a.hasOwnProperty(key))
               {
                  return 1;
               }
            }
         }
         return result;
      }
      
      private static function byteArrayCompare(a:ByteArray, b:ByteArray) : int
      {
         var i:int = 0;
         var result:int = 0;
         if(a.length != b.length)
         {
            if(a.length < b.length)
            {
               result = -1;
            }
            else
            {
               result = 1;
            }
         }
         else
         {
            a.position = 0;
            b.position = 0;
            for(i = 0; i < a.length; i++)
            {
               result = ObjectUtil.numericCompare(a.readByte(),b.readByte());
               if(result != 0)
               {
                  i = a.length;
               }
            }
         }
         return result;
      }
      
      private static function listCompare(a:IList, b:IList, currentDepth:int, desiredDepth:int, refs:Dictionary, excludes:Array) : int
      {
         var i:int = 0;
         var result:int = 0;
         if(a.length != b.length)
         {
            if(a.length < b.length)
            {
               result = -1;
            }
            else
            {
               result = 1;
            }
         }
         else
         {
            for(i = 0; i < a.length; i++)
            {
               result = internalCompare(a.getItemAt(i),b.getItemAt(i),currentDepth + 1,desiredDepth,refs,excludes);
               if(result != 0)
               {
                  i = a.length;
               }
            }
         }
         return result;
      }
      
      public static function toString(value:Object, namespaceURIs:Array = null, exclude:Array = null, indent:int = 0, printTypes:Boolean = false, refs:Dictionary = null) : String
      {
         return internalToString(value,indent,refs,namespaceURIs,exclude,printTypes);
      }
      
      static function internalToString(value:Object, indent:int = 0, refs:Dictionary = null, namespaceURIs:Array = null, exclude:Array = null, printTypes:Boolean = false, printSummary:Boolean = false, cds:ConcreteDataService = null) : String
      {
         var str:String = null;
         var adate:Date = null;
         var s:String = null;
         var ix:int = 0;
         var lv:Boolean = false;
         var ai:int = 0;
         var dl:DataList = null;
         var arrValue:* = undefined;
         var l:String = null;
         var classInfo:Object = null;
         var properties:Array = null;
         var id:Object = null;
         var prop:* = undefined;
         var j:int = 0;
         var refCds:ConcreteDataService = null;
         var valueStr:String = null;
         var propValue:Object = null;
         var assoc:ManagedAssociation = null;
         var summaryFlag:Boolean = false;
         var refIds:Object = null;
         var type:String = value == null?"null":typeof value;
         switch(type)
         {
            case "boolean":
            case "number":
               return value.toString();
            case "string":
               return "\"" + value.toString() + "\"";
            case "object":
               if(value is Date)
               {
                  adate = value as Date;
                  s = adate.toString();
                  if(adate.getMilliseconds() != 0)
                  {
                     ix = s.indexOf(":",s.indexOf(":") + 1) + 3;
                     s = s.substring(0,ix) + "." + adate.getMilliseconds() + s.substring(ix);
                  }
                  return s;
               }
               if(value is XMLNode)
               {
                  return value.toString();
               }
               if(value is Class)
               {
                  return "(" + getQualifiedClassName(value) + ")";
               }
               if(value is Array || value is ListCollectionView)
               {
                  str = "[";
                  lv = false;
                  if(value is ListCollectionView && value.list is DataList)
                  {
                     dl = value.list as DataList;
                     if(!dl.fetched)
                     {
                        str = str + "<not-fetched>]";
                        return str;
                     }
                     var value:Object = dl.localReferences;
                  }
                  for(ai = 0; ai < value.length; ai++)
                  {
                     if(ai != 0)
                     {
                        str = str + ",";
                     }
                     arrValue = value is Array?value[ai]:value.getItemAt(ai);
                     l = ConcreteDataService.itemToString(arrValue,cds == null?null:cds.destination,indent,refs,exclude,false);
                     if(!lv && l != null && l.indexOf("\n") != -1)
                     {
                        lv = true;
                     }
                     if(lv)
                     {
                        str = newline(str,indent);
                     }
                     str = str + l;
                  }
                  str = str + "]";
                  return str;
               }
               classInfo = ObjectUtil.getClassInfo(value,exclude,{
                  "includeReadOnly":true,
                  "uris":namespaceURIs
               });
               properties = classInfo.properties;
               if(!printTypes)
               {
                  str = "";
               }
               else
               {
                  str = "(" + classInfo.name + ")";
               }
               if(refs == null)
               {
                  var refs:Dictionary = new Dictionary(true);
                  refCount = 0;
               }
               id = refs[value];
               if(id != null)
               {
                  if(id is ConcreteDataService)
                  {
                     refCds = id as ConcreteDataService;
                     str = str + (refs[value] = ConcreteDataService.itemToString(value,refCds.destination,0,refs,null,true));
                  }
                  else if(id is String)
                  {
                     str = str + "(recursive ref to: ";
                     if(id.length > 30)
                     {
                        str = str + (id.substring(0,10) + " ... " + id.substring(id.length - 10));
                     }
                     else
                     {
                        str = str + id;
                     }
                     str = str + ")";
                  }
                  return str;
               }
               if(value != null)
               {
                  if(printTypes)
                  {
                     str = str + ("#" + refCount.toString());
                  }
               }
               var indent:int = indent + 2;
               if(!printTypes)
               {
                  str = str + (classInfo.name == "Object"?"{":classInfo.name + " {");
               }
               if(cds != null)
               {
                  refs[value] = cds;
               }
               else
               {
                  refs[value] = refCount;
               }
               for(j = 0; j < properties.length; j++)
               {
                  prop = properties[j];
                  try
                  {
                     propValue = value[prop];
                     assoc = null;
                     if(cds != null)
                     {
                        summaryFlag = true;
                        assoc = cds.metadata.associations[prop];
                        if(propValue == null && assoc != null)
                        {
                           refIds = value.referencedIds;
                           if(refIds != null)
                           {
                              propValue = refIds[prop];
                           }
                           summaryFlag = false;
                        }
                     }
                  }
                  catch(e:Error)
                  {
                     propValue = "<Error accessing property: " + prop + ": " + e.name + ": " + e.message + " stack: " + e.getStackTrace();
                  }
                  valueStr = ConcreteDataService.itemToString(propValue,assoc == null?null:assoc.destination,indent,refs,exclude,assoc != null && summaryFlag?Boolean(true):Boolean(false));
                  str = newline(str,indent);
                  str = str + (prop.toString() + " = ");
                  str = str + valueStr;
               }
               indent = indent - 2;
               if(!printTypes)
               {
                  str = newline(str,indent);
                  str = str + "}";
               }
               return str;
            case "xml":
               return value.toString();
            default:
               return "(" + type + ")";
         }
      }
      
      static function newline(str:String, n:int = 0) : String
      {
         var result:String = str;
         result = result + "\n";
         for(var i:int = 0; i < n; i++)
         {
            result = result + " ";
         }
         return result;
      }
      
      static function reachableFrom(obj:Object, path:Object, target:Object) : Boolean
      {
         var propName:String = null;
         var index:Number = NaN;
         var propNames:Array = path.toString().split(".");
         var currentValue:Object = target;
         for(var i:int = 0; i < propNames.length; i++)
         {
            if(currentValue === obj)
            {
               return true;
            }
            if(currentValue == null)
            {
               return false;
            }
            propName = propNames[i];
            if(currentValue is IList)
            {
               index = Number(propName);
               try
               {
                  currentValue = IList(currentValue).getItemAt(index);
               }
               catch(e:Error)
               {
                  return false;
               }
            }
            else if(propertyFetched(currentValue,propName))
            {
               currentValue = currentValue[propName];
            }
            else
            {
               return true;
            }
         }
         return false;
      }
      
      private static function createSubPropertyChangeHandler(obj:Object, property:Object) : Function
      {
         var f:Function = function(event:PropertyChangeEvent):void
         {
            if(!reachableFrom(obj,event.property,event.target))
            {
               obj.dispatchEvent(Managed.createUpdateEvent(obj as IManaged,property,event));
            }
         };
         return f;
      }
   }
}
