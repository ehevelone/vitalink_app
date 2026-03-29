const db = require("./services/db");

exports.handler = async (event) => {

try{

const { user_id } = JSON.parse(event.body);

if(!user_id){
  return {
    statusCode:400,
    body: JSON.stringify({ error:"Missing user_id" })
  };
}

const result = await db.query(
`
SELECT id, name
FROM profiles
WHERE user_id = $1
ORDER BY name ASC
`,
[user_id]
);

return {
  statusCode:200,
  body: JSON.stringify({
    success:true,
    profiles: result.rows
  })
};

}catch(err){

console.error(err);

return {
  statusCode:500,
  body: JSON.stringify({ error:"Server error" })
};

}

};