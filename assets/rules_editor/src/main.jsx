// BASA rule editor: GoRules' JDM Editor mounted into the /admin/rules/:key
// page by the RulesEditor LiveView hook, plus josdejong's JSON editor for
// the rule's raw JSON and the test input (mountJson).
// Loaded only on that page. Monaco (the code editor inside function nodes)
// comes from this bundle, never from a CDN.
import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { DecisionGraph, JdmConfigProvider } from "@gorules/jdm-editor";
import "@gorules/jdm-editor/dist/style.css";
import JSONEditor from "jsoneditor";
import "jsoneditor/dist/jsoneditor.css";
import { loader } from "@monaco-editor/react";
import * as monaco from "monaco-editor";
import editorWorker from "monaco-editor/esm/vs/editor/editor.worker?worker";
import jsonWorker from "monaco-editor/esm/vs/language/json/json.worker?worker";
import tsWorker from "monaco-editor/esm/vs/language/typescript/ts.worker?worker";

self.MonacoEnvironment = {
  getWorker(_id, label) {
    if (label === "json") return new jsonWorker();
    if (label === "typescript" || label === "javascript") return new tsWorker();
    return new editorWorker();
  },
};
loader.config({ monaco });

function Editor({ initial, api, disabled }) {
  const [graph, setGraph] = useState(initial);
  const [simulate, setSimulate] = useState(undefined);
  api.setSimulate = setSimulate;
  api.setGraph = setGraph;
  api.getGraph = () => graph;

  return (
    <JdmConfigProvider>
      <DecisionGraph
        value={graph}
        disabled={disabled}
        simulate={simulate}
        onChange={(value) => {
          setGraph(value);
          api.onChange && api.onChange(value);
        }}
      />
    </JdmConfigProvider>
  );
}

// mount(element, {graph, disabled, onChange}) -> {getGraph, setGraph, setSimulate, unmount}
export function mount(element, { graph, disabled = false, onChange }) {
  const api = { onChange };
  const root = createRoot(element);
  root.render(<Editor initial={graph} api={api} disabled={disabled} />);

  return {
    getGraph: () => api.getGraph && api.getGraph(),
    setGraph: (value) => api.setGraph && api.setGraph(value),
    setSimulate: (value) => api.setSimulate && api.setSimulate(value),
    unmount: () => root.unmount(),
  };
}

// JSON editor (josdejong/jsoneditor) for other JSON on the page.
// mountJson(element, {value, modes, onChange}) -> {get, getText, set, refresh, destroy}
// get() returns the parsed value, or throws when the text isn't valid JSON.
export function mountJson(element, { value, modes = ["code", "tree"], onChange }) {
  const editor = new JSONEditor(element, {
    mode: modes[0],
    modes,
    mainMenuBar: true,
    navigationBar: false,
    statusBar: true,
    onChange: () => onChange && onChange(),
  });
  editor.set(value);

  return {
    get: () => editor.get(),
    getText: () => editor.getText(),
    set: (v) => editor.set(v),
    // After being hidden: the code view measures itself again
    refresh: () => editor.aceEditor && editor.aceEditor.resize(),
    destroy: () => editor.destroy(),
  };
}
