/**
 *   Licensed to the Apache Software Foundation (ASF) under one
 *   or more contributor license agreements.  See the NOTICE file
 *   distributed with this work for additional information
 *   regarding copyright ownership.  The ASF licenses this file
 *   to you under the Apache License, Version 2.0 (the
 *   "License"); you may not use this file except in compliance
 *   with the License.  You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */
package com.qlangtech.tis.solrdao;

import com.alibaba.fastjson.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * @author 百岁（baisui@qlangtech.com）
 * @date 2021-01-27 13:08
 *
 * feature/chatbi-only: 由已裁剪的 tis-solrconfig-parser 迁移至 tis-console，
 * 并移除依赖 SolrFieldsParser 的 parseSchemaResult 方法。
 */
public class SchemaResult extends SchemaMetaContent {

    private static final Logger logger = LoggerFactory.getLogger(SchemaResult.class);


    private boolean success = false;

    // 模板索引的id编号
    private int tplAppId;

    // protected final boolean xmlPost;

    public boolean isSuccess() {
        return success;
    }

    public SchemaResult faild() {
        this.success = false;
        return this;
    }

    public static SchemaResult create(ISchema parseResult, byte[] schemaContent) {
        SchemaResult schema = new SchemaResult();
        schema.parseResult = parseResult;
        schema.content = schemaContent;
        schema.success = true;
        return schema;
    }

    @Override
    protected void appendExtraProps(JSONObject schema) {
        if (this.getTplAppId() > 0) {
            schema.put("tplAppId", this.getTplAppId());
        }
    }

    /**
     * feature/chatbi-only: 原实现基于 SolrFieldsParser 解析校验 schema.xml，
     * 该解析器已随 tis-solrconfig-parser 一并裁剪——本版本不支持 schema 解析校验。
     * 此处必须快速失败：绝不能返回"解析成功"的假结果让未校验的配置入库。
     */
    public static SchemaResult parseSchemaResult(com.qlangtech.tis.runtime.module.misc.IMessageHandler module,
                                                 com.alibaba.citrus.turbine.Context context, byte[] schemaContent, boolean shallValidate
            , ISchemaFieldTypeContext schemaPlugin) {
        throw new UnsupportedOperationException(
                "Solr schema 解析能力已随 tis-solrconfig-parser 在 chatbi-only 分支裁剪，"
                        + "不再支持 schema 解析校验。如需该能力请回退全量分支或引入独立 schema 校验插件。");
    }


    public int getTplAppId() {
        return tplAppId;
    }

    public void setTplAppId(int tplAppId) {
        this.tplAppId = tplAppId;
    }

    private SchemaResult() {
        super();
        //this.xmlPost = xmlPost;
    }
}
