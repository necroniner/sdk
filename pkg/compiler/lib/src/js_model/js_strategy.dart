// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.js_model.strategy;

import 'package:kernel/ast.dart' as ir;

import '../backend_strategy.dart';
import '../common.dart';
import '../common/codegen.dart' show CodegenRegistry;
import '../common/tasks.dart';
import '../common/work.dart';
import '../compiler.dart';
import '../deferred_load.dart' hide WorkItem;
import '../dump_info.dart';
import '../elements/entities.dart';
import '../enqueue.dart';
import '../io/kernel_source_information.dart'
    show KernelSourceInformationStrategy;
import '../io/source_information.dart';
import '../inferrer/abstract_value_domain.dart';
import '../inferrer/type_graph_inferrer.dart';
import '../inferrer/types.dart';
import '../js/js_source_mapping.dart';
import '../js_backend/backend.dart';
import '../js_backend/inferred_data.dart';
import '../js_backend/namer.dart';
import '../js_backend/native_data.dart';
import '../js_emitter/code_emitter_task.dart';
import '../kernel/kernel_strategy.dart';
import '../native/behavior.dart';
import '../options.dart';
import '../ssa/builder_kernel.dart';
import '../ssa/nodes.dart';
import '../ssa/ssa.dart';
import '../ssa/types.dart';
import '../tracer.dart';
import '../universe/codegen_world_builder.dart';
import '../universe/selector.dart';
import '../universe/world_builder.dart';
import '../universe/world_impact.dart';
import '../world.dart';
import 'closure.dart';
import 'element_map.dart';
import 'element_map_impl.dart';
import 'js_world.dart';
import 'js_world_builder.dart';
import 'locals.dart';

class JsBackendStrategy implements BackendStrategy {
  final Compiler _compiler;
  JsKernelToElementMap _elementMap;

  JsBackendStrategy(this._compiler);

  @deprecated
  JsToElementMap get elementMap {
    assert(_elementMap != null,
        "JsBackendStrategy.elementMap has not been created yet.");
    return _elementMap;
  }

  @override
  JClosedWorld createJClosedWorld(
      KClosedWorld closedWorld, OutputUnitData outputUnitData) {
    KernelFrontEndStrategy strategy = _compiler.frontendStrategy;
    _elementMap = new JsKernelToElementMap(
        _compiler.reporter,
        _compiler.environment,
        strategy.elementMap,
        closedWorld.liveMemberUsage,
        closedWorld.annotationsData);
    GlobalLocalsMap _globalLocalsMap = new GlobalLocalsMap();
    ClosureDataBuilder closureDataBuilder = new ClosureDataBuilder(
        _elementMap, _globalLocalsMap, _compiler.options);
    JsClosedWorldBuilder closedWorldBuilder = new JsClosedWorldBuilder(
        _elementMap,
        _globalLocalsMap,
        closureDataBuilder,
        _compiler.options,
        _compiler.abstractValueStrategy);
    return closedWorldBuilder.convertClosedWorld(
        closedWorld, strategy.closureModels, outputUnitData);
  }

  @override
  void registerJClosedWorld(covariant JsClosedWorld closedWorld) {
    _elementMap = closedWorld.elementMap;
  }

  @override
  SourceInformationStrategy get sourceInformationStrategy {
    if (!_compiler.options.generateSourceMap) {
      return const JavaScriptSourceInformationStrategy();
    }
    return new KernelSourceInformationStrategy(this);
  }

  @override
  SsaBuilder createSsaBuilder(CompilerTask task, CodegenInputs codegen,
      SourceInformationStrategy sourceInformationStrategy) {
    return new KernelSsaBuilder(
        task,
        _compiler.options,
        _compiler.reporter,
        _compiler.dumpInfoTask,
        // ignore:deprecated_member_use_from_same_package
        elementMap,
        codegen.namer,
        codegen.emitter,
        codegen.tracer,
        sourceInformationStrategy);
  }

  @override
  WorkItemBuilder createCodegenWorkItemBuilder(
      JClosedWorld closedWorld,
      GlobalTypeInferenceResults globalInferenceResults,
      CodegenInputs codegen) {
    return new KernelCodegenWorkItemBuilder(
        _compiler.backend, closedWorld, globalInferenceResults, codegen);
  }

  @override
  CodegenWorldBuilder createCodegenWorldBuilder(
      NativeBasicData nativeBasicData,
      JClosedWorld closedWorld,
      SelectorConstraintsStrategy selectorConstraintsStrategy) {
    return new CodegenWorldBuilderImpl(
        closedWorld, selectorConstraintsStrategy);
  }

  @override
  SourceSpan spanFromSpannable(Spannable spannable, Entity currentElement) {
    return _elementMap.getSourceSpan(spannable, currentElement);
  }

  @override
  TypesInferrer createTypesInferrer(
      JClosedWorld closedWorld, InferredDataBuilder inferredDataBuilder) {
    return new TypeGraphInferrer(_compiler, closedWorld, inferredDataBuilder);
  }
}

class KernelCodegenWorkItemBuilder implements WorkItemBuilder {
  final JavaScriptBackend _backend;
  final JClosedWorld _closedWorld;
  final GlobalTypeInferenceResults _globalInferenceResults;
  final CodegenInputs _codegen;

  KernelCodegenWorkItemBuilder(this._backend, this._closedWorld,
      this._globalInferenceResults, this._codegen);

  @override
  WorkItem createWorkItem(MemberEntity entity) {
    if (entity.isAbstract) return null;
    return new KernelCodegenWorkItem(
        _backend, _closedWorld, _globalInferenceResults, _codegen, entity);
  }
}

class KernelCodegenWorkItem extends WorkItem {
  final JavaScriptBackend _backend;
  final JClosedWorld _closedWorld;
  @override
  final MemberEntity element;
  final GlobalTypeInferenceResults _globalInferenceResults;
  final CodegenInputs _codegen;

  KernelCodegenWorkItem(this._backend, this._closedWorld,
      this._globalInferenceResults, this._codegen, this.element);

  @override
  WorldImpact run() {
    return _backend.generateCode(
        this, _closedWorld, _globalInferenceResults, _codegen);
  }
}

/// Task for building SSA from kernel IR loaded from .dill.
class KernelSsaBuilder implements SsaBuilder {
  final CompilerTask _task;
  final CompilerOptions _options;
  final DiagnosticReporter _reporter;
  final DumpInfoTask _dumpInfoTask;
  final JsToElementMap _elementMap;
  final ModularNamer _namer;
  final ModularEmitter _emitter;
  final Tracer _tracer;
  final SourceInformationStrategy _sourceInformationStrategy;

  // TODO(johnniwinther,sra): Inlining decisions should not be based on the
  // order in which ssa graphs are built.
  FunctionInlineCache _inlineCache;

  KernelSsaBuilder(
      this._task,
      this._options,
      this._reporter,
      this._dumpInfoTask,
      this._elementMap,
      this._namer,
      this._emitter,
      this._tracer,
      this._sourceInformationStrategy);

  @override
  HGraph build(MemberEntity member, JClosedWorld closedWorld,
      GlobalTypeInferenceResults results, CodegenRegistry registry) {
    _inlineCache ??= new FunctionInlineCache(closedWorld.annotationsData);
    return _task.measure(() {
      KernelSsaGraphBuilder builder = new KernelSsaGraphBuilder(
          _options,
          _reporter,
          member,
          _elementMap.getMemberThisType(member),
          _dumpInfoTask,
          _elementMap,
          results,
          closedWorld,
          registry,
          _namer,
          _emitter,
          _tracer,
          _sourceInformationStrategy,
          _inlineCache);
      return builder.build();
    });
  }
}

class KernelToTypeInferenceMapImpl implements KernelToTypeInferenceMap {
  final GlobalTypeInferenceResults _globalInferenceResults;
  GlobalTypeInferenceMemberResult _targetResults;

  KernelToTypeInferenceMapImpl(
      MemberEntity target, this._globalInferenceResults) {
    _targetResults = _resultOf(target);
  }

  GlobalTypeInferenceMemberResult _resultOf(MemberEntity e) =>
      _globalInferenceResults
          .resultOfMember(e is ConstructorBodyEntity ? e.constructor : e);

  @override
  AbstractValue getReturnTypeOf(FunctionEntity function) {
    return AbstractValueFactory.inferredReturnTypeForElement(
        function, _globalInferenceResults);
  }

  @override
  AbstractValue receiverTypeOfInvocation(
      ir.MethodInvocation node, AbstractValueDomain abstractValueDomain) {
    return _targetResults.typeOfSend(node);
  }

  @override
  AbstractValue receiverTypeOfGet(ir.PropertyGet node) {
    return _targetResults.typeOfSend(node);
  }

  @override
  AbstractValue receiverTypeOfDirectGet(ir.DirectPropertyGet node) {
    return _targetResults.typeOfSend(node);
  }

  @override
  AbstractValue receiverTypeOfSet(
      ir.PropertySet node, AbstractValueDomain abstractValueDomain) {
    return _targetResults.typeOfSend(node);
  }

  @override
  AbstractValue typeOfListLiteral(
      ir.ListLiteral listLiteral, AbstractValueDomain abstractValueDomain) {
    return _globalInferenceResults.typeOfListLiteral(listLiteral) ??
        abstractValueDomain.dynamicType;
  }

  @override
  AbstractValue typeOfIterator(ir.ForInStatement node) {
    return _targetResults.typeOfIterator(node);
  }

  @override
  AbstractValue typeOfIteratorCurrent(ir.ForInStatement node) {
    return _targetResults.typeOfIteratorCurrent(node);
  }

  @override
  AbstractValue typeOfIteratorMoveNext(ir.ForInStatement node) {
    return _targetResults.typeOfIteratorMoveNext(node);
  }

  @override
  bool isJsIndexableIterator(
      ir.ForInStatement node, AbstractValueDomain abstractValueDomain) {
    AbstractValue mask = typeOfIterator(node);
    return abstractValueDomain.isJsIndexableAndIterable(mask).isDefinitelyTrue;
  }

  @override
  AbstractValue inferredIndexType(ir.ForInStatement node) {
    return AbstractValueFactory.inferredResultTypeForSelector(
        new Selector.index(), typeOfIterator(node), _globalInferenceResults);
  }

  @override
  AbstractValue getInferredTypeOf(MemberEntity member) {
    return AbstractValueFactory.inferredTypeForMember(
        member, _globalInferenceResults);
  }

  @override
  AbstractValue getInferredTypeOfParameter(Local parameter) {
    return AbstractValueFactory.inferredTypeForParameter(
        parameter, _globalInferenceResults);
  }

  @override
  AbstractValue resultTypeOfSelector(Selector selector, AbstractValue mask) {
    return AbstractValueFactory.inferredResultTypeForSelector(
        selector, mask, _globalInferenceResults);
  }

  @override
  AbstractValue typeFromNativeBehavior(
      NativeBehavior nativeBehavior, JClosedWorld closedWorld) {
    return AbstractValueFactory.fromNativeBehavior(nativeBehavior, closedWorld);
  }
}
