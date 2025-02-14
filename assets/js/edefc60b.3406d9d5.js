"use strict";(self.webpackChunk=self.webpackChunk||[]).push([[624],{3739:(e,n,r)=>{r.r(n),r.d(n,{assets:()=>o,contentTitle:()=>d,default:()=>h,frontMatter:()=>c,metadata:()=>s,toc:()=>a});const s=JSON.parse('{"id":"performance","title":"Performance","description":"The performance of Panko is measured using microbenchmarks and load testing.","source":"@site/docs/performance.md","sourceDirName":".","slug":"/performance","permalink":"/performance","draft":false,"unlisted":false,"tags":[],"version":"current","frontMatter":{"id":"performance","title":"Performance","sidebar_label":"Performance"},"sidebar":"docs","previous":{"title":"Getting Started","permalink":"/getting-started"},"next":{"title":"Design Choices","permalink":"/design-choices"}}');var t=r(4848),i=r(8453);const c={id:"performance",title:"Performance",sidebar_label:"Performance"},d=void 0,o={},a=[{value:"Microbenchmarks",id:"microbenchmarks",level:2},{value:"Real-world benchmark",id:"real-world-benchmark",level:2}];function l(e){const n={a:"a",code:"code",em:"em",h2:"h2",p:"p",table:"table",tbody:"tbody",td:"td",th:"th",thead:"thead",tr:"tr",...(0,i.R)(),...e.components};return(0,t.jsxs)(t.Fragment,{children:[(0,t.jsx)(n.p,{children:"The performance of Panko is measured using microbenchmarks and load testing."}),"\n",(0,t.jsx)(n.h2,{id:"microbenchmarks",children:"Microbenchmarks"}),"\n",(0,t.jsx)(n.p,{children:"The following microbenchmarks are run on MacBook Pro (16-inch, 2021, M1 Max), Ruby 3.2.0 with Rails 7.0.5\ndemonstrating the performance of ActiveModelSerializers 0.10.13 and Panko 0.8.0"}),"\n",(0,t.jsxs)(n.table,{children:[(0,t.jsx)(n.thead,{children:(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.th,{children:"Benchmark"}),(0,t.jsx)(n.th,{children:"AMS ip/s"}),(0,t.jsx)(n.th,{children:"Panko ip/s"})]})}),(0,t.jsxs)(n.tbody,{children:[(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"Simple_Posts_2300"}),(0,t.jsx)(n.td,{children:"11.72"}),(0,t.jsx)(n.td,{children:"523.05"})]}),(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"Simple_Posts_50"}),(0,t.jsx)(n.td,{children:"557.29"}),(0,t.jsx)(n.td,{children:"23,011.9"})]}),(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"HasOne_Posts_2300"}),(0,t.jsx)(n.td,{children:"5.91"}),(0,t.jsx)(n.td,{children:"233.44"})]}),(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"HasOne_Posts_50"}),(0,t.jsx)(n.td,{children:"285.8"}),(0,t.jsx)(n.td,{children:"10,362.79"})]})]})]}),"\n",(0,t.jsx)(n.h2,{id:"real-world-benchmark",children:"Real-world benchmark"}),"\n",(0,t.jsxs)(n.p,{children:["The real-world benchmark here is endpoint which serializes 7,884 entries with 48 attributes and no associations.\nThe benchmark took place in environment that simulates production environment and run using ",(0,t.jsx)(n.code,{children:"wrk"})," from machine on the same cluster."]}),"\n",(0,t.jsxs)(n.table,{children:[(0,t.jsx)(n.thead,{children:(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.th,{children:"Metric"}),(0,t.jsx)(n.th,{children:"AMS"}),(0,t.jsx)(n.th,{children:"Panko"})]})}),(0,t.jsxs)(n.tbody,{children:[(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"Avg Response Time"}),(0,t.jsx)(n.td,{children:"4.89s"}),(0,t.jsx)(n.td,{children:"1.48s"})]}),(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"Max Response Time"}),(0,t.jsx)(n.td,{children:"5.42s"}),(0,t.jsx)(n.td,{children:"1.83s"})]}),(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"99th Response Time"}),(0,t.jsx)(n.td,{children:"5.42s"}),(0,t.jsx)(n.td,{children:"1.74s"})]}),(0,t.jsxs)(n.tr,{children:[(0,t.jsx)(n.td,{children:"Total Requests"}),(0,t.jsx)(n.td,{children:"61"}),(0,t.jsx)(n.td,{children:"202"})]})]})]}),"\n",(0,t.jsx)(n.p,{children:(0,t.jsxs)(n.em,{children:["Thanks to ",(0,t.jsx)(n.a,{href:"https://www.bringg.com",children:"Bringg"})," for providing the infrastructure for the benchmarks"]})})]})}function h(e={}){const{wrapper:n}={...(0,i.R)(),...e.components};return n?(0,t.jsx)(n,{...e,children:(0,t.jsx)(l,{...e})}):l(e)}},8453:(e,n,r)=>{r.d(n,{R:()=>c,x:()=>d});var s=r(6540);const t={},i=s.createContext(t);function c(e){const n=s.useContext(i);return s.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function d(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(t):e.components||t:c(e.components),s.createElement(i.Provider,{value:n},e.children)}}}]);