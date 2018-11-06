package mx.data
{
   import flash.utils.Dictionary;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   import mx.collections.ArrayCollection;
   import mx.core.mx_internal;
   import mx.rpc.AbstractOperation;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   import mx.utils.DescribeTypeCache;
   import mx.utils.ObjectUtil;
   
   [ExcludeClass]
   public class TypeUtility
   {
      
      private static var TYPE_INT:String = "int";
      
      private static var TYPE_STRING:String = "String";
      
      private static var TYPE_BOOLEAN:String = "Boolean";
      
      private static var TYPE_NUMBER:String = "Number";
      
      private static var TYPE_DATE:String = "Date";
      
      private static var TYPE_ARRAYCOLLECTION:String = "mx.collections::ArrayCollection";
      
      private static var TYPE_ARRAYCOLLECTION_2:String = "mx.collections.ArrayCollection";
      
      private static var TYPE_ARRAY:String = "Array";
      
      private static var propertyTypeMap:Dictionary;
      
      private static var arrayTypeMap:Dictionary;
       
      
      public function TypeUtility()
      {
         super();
      }
      
      public static function getType(clazz:Class, propertyName:String) : String
      {
         var description:XML = null;
         if(!propertyTypeMap)
         {
            propertyTypeMap = new Dictionary(false);
         }
         if(!propertyTypeMap[clazz])
         {
            propertyTypeMap[clazz] = new Dictionary(false);
         }
         var type:String = propertyTypeMap[clazz][propertyName];
         if(type != null)
         {
            return type;
         }
         var obj:Object = new clazz();
         var model:Object = getModel(obj);
         if(model != null && model.hasOwnProperty("getPropertyType"))
         {
            type = model.getPropertyType(propertyName);
         }
         if(type == null || type.length < 1)
         {
            if(obj.hasOwnProperty("__getPropertyType"))
            {
               type = obj.__getPropertyType(propertyName);
            }
         }
         if(type == null || type.length < 1)
         {
            description = DescribeTypeCache.describeType(obj).typeDescription;
            type = description..*.(name() == "variable" || name() == "accessor").(@name == propertyName).@type;
         }
         propertyTypeMap[clazz][propertyName] = type;
         return type;
      }
      
      public static function getArrayType(clazz:Class, propertyName:String) : Class
      {
         var value:String = null;
         var obj:Object = null;
         var description:XML = null;
         var list:XMLList = null;
         var name:String = null;
         if(!arrayTypeMap)
         {
            arrayTypeMap = new Dictionary(false);
         }
         if(!arrayTypeMap[clazz])
         {
            arrayTypeMap[clazz] = new Dictionary(false);
         }
         var type:Class = arrayTypeMap[clazz][propertyName];
         if(type != null)
         {
            return type;
         }
         var classInfo:Object = ObjectUtil.getClassInfo(clazz,null,null);
         var metadataInfo:Object = classInfo["metadata"];
         if(metadataInfo.hasOwnProperty(propertyName) && metadataInfo[propertyName].hasOwnProperty("ArrayElementType"))
         {
            for each(value in metadataInfo[propertyName]["ArrayElementType"])
            {
               type = getDefinitionByName(value) as Class;
            }
         }
         else
         {
            obj = new clazz();
            description = DescribeTypeCache.describeType(clazz).typeDescription;
            list = description..implementsInterface.(@type == "fr.vo::IModelType");
            if(list.length() > 0 && obj.hasOwnProperty("getCollectionBase"))
            {
               name = obj.getCollectionBase(propertyName);
               if(name != null && name.length > 0)
               {
                  type = getDefinitionByName(name) as Class;
               }
            }
            else if(obj.hasOwnProperty("__getCollectionBase"))
            {
               name = obj.__getCollectionBase(propertyName);
               if(name != null && name.length > 0)
               {
                  type = getDefinitionByName(name) as Class;
               }
            }
         }
         if(type != null)
         {
            arrayTypeMap[clazz][propertyName] = type;
         }
         return type;
      }
      
      public static function getProperties(obj:Object) : Array
      {
         var description:XML = null;
         var list:XMLList = null;
         description = DescribeTypeCache.describeType(obj).typeDescription;
         list = description..implementsInterface.(@type == "fr.vo::IModelType");
         if(list.length() > 0)
         {
            if(obj.hasOwnProperty("getDataProperties"))
            {
               return obj.getDataProperties();
            }
         }
         if(obj.hasOwnProperty("__getDataProperties"))
         {
            return obj.__getDataProperties();
         }
         return null;
      }
      
      private static function getModel(obj:Object) : Object
      {
         var model:Object = null;
         var description:XML = null;
         var list:XMLList = null;
         if(obj.hasOwnProperty("_model"))
         {
            model = obj["_model"];
            description = DescribeTypeCache.describeType(model).typeDescription;
            list = description..implementsInterface.(@type == "com.adobe.fiber.valueobjects::IModelType");
            if(list.length() > 0)
            {
               return model;
            }
         }
         return null;
      }
      
      public static function getXPathArray(xPath:String) : Array
      {
         if(xPath == null || xPath == "" || xPath == "/")
         {
            return null;
         }
         var arr:Array = xPath.split("/");
         arr.shift();
         return arr;
      }
      
      public static function isPrimitive(type:String) : Boolean
      {
         return type == TYPE_INT || type == TYPE_STRING || type == TYPE_BOOLEAN || type == TYPE_NUMBER || type == TYPE_DATE;
      }
      
      public static function isDate(type:String) : Boolean
      {
         return type == TYPE_DATE;
      }
      
      public static function isArrayCollection(type:String) : Boolean
      {
         return type == TYPE_ARRAYCOLLECTION || type == TYPE_ARRAYCOLLECTION_2;
      }
      
      public static function isArray(type:String) : Boolean
      {
         return type == TYPE_ARRAY;
      }
      
      public static function getDate(value:Object) : Date
      {
         return new Date(Date.parse(value));
      }
      
      public static function getUnderScoreName(clazz:Class, result:Object, key:String) : String
      {
         if(clazz && !result.hasOwnProperty(key) && result.hasOwnProperty("_" + key))
         {
            return "_" + key;
         }
         return key;
      }
      
      public static function clear() : void
      {
         propertyTypeMap = null;
         arrayTypeMap = null;
      }
      
      private static function isObject(obj:Object) : Boolean
      {
         return getQualifiedClassName(obj) == "Object" || getQualifiedClassName(obj) == "mx.utils::ObjectProxy";
      }
      
      public static function convertResultEventHandler(event:ResultEvent, operation:AbstractOperation) : void
      {
         var result:Object = event.result;
         if(operation.resultElementType != null && !isObject(operation.resultElementType) && result != null)
         {
            if((result is ArrayCollection || result is Array) && result.length > 0 && isObject(result[0]))
            {
               event.mx_internal::setResult(convertListToStrongType(result,operation.resultElementType));
            }
         }
         else if(operation.resultType != null && !isObject(operation.resultType) && result != null && isObject(result))
         {
            event.mx_internal::setResult(convertToStrongType(result,operation.resultType));
         }
         clear();
      }
      
      public static function convertSingleValuedMapEventHandler(event:ResultEvent, operation:AbstractOperation) : void
      {
         var prop:* = null;
         var result:Object = event.result;
         if(isObject(result))
         {
            for(prop in result)
            {
               event.mx_internal::setResult(result[prop]);
            }
            convertResultEventHandler(event,operation);
         }
      }
      
      public static function emptyEventHandler(event:FaultEvent, operation:AbstractOperation) : void
      {
      }
      
      public static function convertListToStrongType(source:Object, clazz:Class, visitedObjects:Dictionary = null) : Object
      {
         if(!(source is ArrayCollection || source is Array))
         {
            return source;
         }
         if(visitedObjects == null)
         {
            visitedObjects = new Dictionary();
         }
         if(visitedObjects[source] != null)
         {
            return visitedObjects[source];
         }
         var result:Array = [];
         for(var i:int = 0; i < source.length; i++)
         {
            if(visitedObjects[source[i]] == null)
            {
               result[i] = convertToStrongType(source[i],clazz,visitedObjects);
               visitedObjects[source[i]] = result[i];
            }
            else
            {
               result[i] = visitedObjects[source[i]];
            }
         }
         var ac:ArrayCollection = new ArrayCollection(result);
         visitedObjects[source] = ac;
         return ac;
      }
      
      public static function convertToStrongType(source:Object, clazz:Class, visitedObjects:Dictionary = null) : Object
      {
         var prop:* = null;
         if(clazz == null)
         {
            return source;
         }
         if(visitedObjects == null)
         {
            visitedObjects = new Dictionary();
         }
         if(visitedObjects[source] != null)
         {
            return visitedObjects[source];
         }
         var res:Object = new clazz();
         if(source is clazz)
         {
            return source;
         }
         for(prop in source)
         {
            assignProperty(source,res,prop,clazz,visitedObjects);
         }
         visitedObjects[source] = res;
         return res;
      }
      
      private static function assignProperty(source:Object, result:Object, property:String, clazz:Class, visitedObjects:Dictionary) : void
      {
         var subClazz:Class = clazz;
         var type:String = TypeUtility.getType(clazz,property);
         var isPrimitive:Boolean = TypeUtility.isPrimitive(type);
         var isArray:Boolean = TypeUtility.isArray(type);
         var isArrayCollection:Boolean = TypeUtility.isArrayCollection(type);
         if(isArray || isArrayCollection)
         {
            isArray = true;
            subClazz = TypeUtility.getArrayType(clazz,property);
         }
         else if(type != null && type.length > 0 && !isPrimitive)
         {
            subClazz = getDefinitionByName(type) as Class;
         }
         if(result.hasOwnProperty(property))
         {
            if(isPrimitive || isObject(subClazz))
            {
               result[property] = source[property];
            }
            else if(isArrayCollection || isArray)
            {
               if(visitedObjects[source[property]] == null)
               {
                  result[property] = convertListToStrongType(source[property],subClazz,visitedObjects);
                  visitedObjects[source[property]] = result[property];
               }
               else
               {
                  result[property] = visitedObjects[source[property]];
               }
            }
            else if(visitedObjects[source[property]] == null)
            {
               result[property] = convertToStrongType(source[property],subClazz,visitedObjects);
               visitedObjects[source[property]] = result[property];
            }
            else
            {
               result[property] = visitedObjects[source[property]];
            }
         }
      }
   }
}
