"use strict";(self.webpackChunk=self.webpackChunk||[]).push([[624],{5680:(e,t,r)=>{r.d(t,{xA:()=>g,yg:()=>y});var n=r(6540);function a(e,t,r){return t in e?Object.defineProperty(e,t,{value:r,enumerable:!0,configurable:!0,writable:!0}):e[t]=r,e}function l(e,t){var r=Object.keys(e);if(Object.getOwnPropertySymbols){var n=Object.getOwnPropertySymbols(e);t&&(n=n.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),r.push.apply(r,n)}return r}function o(e){for(var t=1;t<arguments.length;t++){var r=null!=arguments[t]?arguments[t]:{};t%2?l(Object(r),!0).forEach((function(t){a(e,t,r[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(r)):l(Object(r)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(r,t))}))}return e}function i(e,t){if(null==e)return{};var r,n,a=function(e,t){if(null==e)return{};var r,n,a={},l=Object.keys(e);for(n=0;n<l.length;n++)r=l[n],t.indexOf(r)>=0||(a[r]=e[r]);return a}(e,t);if(Object.getOwnPropertySymbols){var l=Object.getOwnPropertySymbols(e);for(n=0;n<l.length;n++)r=l[n],t.indexOf(r)>=0||Object.prototype.propertyIsEnumerable.call(e,r)&&(a[r]=e[r])}return a}var m=n.createContext({}),p=function(e){var t=n.useContext(m),r=t;return e&&(r="function"==typeof e?e(t):o(o({},t),e)),r},g=function(e){var t=p(e.components);return n.createElement(m.Provider,{value:t},e.children)},c="mdxType",s={inlineCode:"code",wrapper:function(e){var t=e.children;return n.createElement(n.Fragment,{},t)}},u=n.forwardRef((function(e,t){var r=e.components,a=e.mdxType,l=e.originalType,m=e.parentName,g=i(e,["components","mdxType","originalType","parentName"]),c=p(r),u=a,y=c["".concat(m,".").concat(u)]||c[u]||s[u]||l;return r?n.createElement(y,o(o({ref:t},g),{},{components:r})):n.createElement(y,o({ref:t},g))}));function y(e,t){var r=arguments,a=t&&t.mdxType;if("string"==typeof e||a){var l=r.length,o=new Array(l);o[0]=u;var i={};for(var m in t)hasOwnProperty.call(t,m)&&(i[m]=t[m]);i.originalType=e,i[c]="string"==typeof e?e:a,o[1]=i;for(var p=2;p<l;p++)o[p]=r[p];return n.createElement.apply(null,o)}return n.createElement.apply(null,r)}u.displayName="MDXCreateElement"},1496:(e,t,r)=>{r.r(t),r.d(t,{assets:()=>g,contentTitle:()=>m,default:()=>y,frontMatter:()=>i,metadata:()=>p,toc:()=>c});var n=r(8168),a=r(8587),l=(r(6540),r(5680)),o=["components"],i={id:"performance",title:"Performance",sidebar_label:"Performance"},m=void 0,p={unversionedId:"performance",id:"performance",title:"Performance",description:"The performance of Panko is measured using microbenchmarks and load testing.",source:"@site/docs/performance.md",sourceDirName:".",slug:"/performance",permalink:"/performance",draft:!1,tags:[],version:"current",frontMatter:{id:"performance",title:"Performance",sidebar_label:"Performance"},sidebar:"docs",previous:{title:"Getting Started",permalink:"/getting-started"},next:{title:"Design Choices",permalink:"/design-choices"}},g={},c=[{value:"Microbenchmarks",id:"microbenchmarks",level:2},{value:"Real-world benchmark",id:"real-world-benchmark",level:2}],s={toc:c},u="wrapper";function y(e){var t=e.components,r=(0,a.A)(e,o);return(0,l.yg)(u,(0,n.A)({},s,r,{components:t,mdxType:"MDXLayout"}),(0,l.yg)("p",null,"The performance of Panko is measured using microbenchmarks and load testing."),(0,l.yg)("h2",{id:"microbenchmarks"},"Microbenchmarks"),(0,l.yg)("p",null,"The following microbenchmarks are run on MacBook Pro (16-inch, 2021, M1 Max), Ruby 3.2.0 with Rails 7.0.5\ndemonstrating the performance of ActiveModelSerializers 0.10.13 and Panko 0.8.0"),(0,l.yg)("table",null,(0,l.yg)("thead",{parentName:"table"},(0,l.yg)("tr",{parentName:"thead"},(0,l.yg)("th",{parentName:"tr",align:null},"Benchmark"),(0,l.yg)("th",{parentName:"tr",align:null},"AMS ip/s"),(0,l.yg)("th",{parentName:"tr",align:null},"Panko ip/s"))),(0,l.yg)("tbody",{parentName:"table"},(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"Simple_Posts_2300"),(0,l.yg)("td",{parentName:"tr",align:null},"11.72"),(0,l.yg)("td",{parentName:"tr",align:null},"523.05")),(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"Simple_Posts_50"),(0,l.yg)("td",{parentName:"tr",align:null},"557.29"),(0,l.yg)("td",{parentName:"tr",align:null},"23,011.9")),(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"HasOne_Posts_2300"),(0,l.yg)("td",{parentName:"tr",align:null},"5.91"),(0,l.yg)("td",{parentName:"tr",align:null},"233.44")),(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"HasOne_Posts_50"),(0,l.yg)("td",{parentName:"tr",align:null},"285.8"),(0,l.yg)("td",{parentName:"tr",align:null},"10,362.79")))),(0,l.yg)("h2",{id:"real-world-benchmark"},"Real-world benchmark"),(0,l.yg)("p",null,"The real-world benchmark here is endpoint which serializes 7,884 entries with 48 attributes and no associations.\nThe benchmark took place in environment that simulates production environment and run using ",(0,l.yg)("inlineCode",{parentName:"p"},"wrk")," from machine on the same cluster."),(0,l.yg)("table",null,(0,l.yg)("thead",{parentName:"table"},(0,l.yg)("tr",{parentName:"thead"},(0,l.yg)("th",{parentName:"tr",align:null},"Metric"),(0,l.yg)("th",{parentName:"tr",align:null},"AMS"),(0,l.yg)("th",{parentName:"tr",align:null},"Panko"))),(0,l.yg)("tbody",{parentName:"table"},(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"Avg Response Time"),(0,l.yg)("td",{parentName:"tr",align:null},"4.89s"),(0,l.yg)("td",{parentName:"tr",align:null},"1.48s")),(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"Max Response Time"),(0,l.yg)("td",{parentName:"tr",align:null},"5.42s"),(0,l.yg)("td",{parentName:"tr",align:null},"1.83s")),(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"99th Response Time"),(0,l.yg)("td",{parentName:"tr",align:null},"5.42s"),(0,l.yg)("td",{parentName:"tr",align:null},"1.74s")),(0,l.yg)("tr",{parentName:"tbody"},(0,l.yg)("td",{parentName:"tr",align:null},"Total Requests"),(0,l.yg)("td",{parentName:"tr",align:null},"61"),(0,l.yg)("td",{parentName:"tr",align:null},"202")))),(0,l.yg)("p",null,(0,l.yg)("em",{parentName:"p"},"Thanks to ",(0,l.yg)("a",{parentName:"em",href:"https://www.bringg.com"},"Bringg")," for providing the infrastructure for the benchmarks")))}y.isMDXComponent=!0}}]);