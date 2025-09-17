const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.cert('C:\\Users\\hp\\Downloads\\campusone-76fbd-0b84ff9f0a69.json'),
  projectId: 'campusone-76fbd'
});

const db = admin.firestore();

async function addFeesCustomFields() {
  try {
    const orgRef = db.collection('orgs').doc('demo');
    const orgDoc = await orgRef.get();
    
    if (!orgDoc.exists) {
      console.log('Organization not found');
      return;
    }
    
    const currentData = orgDoc.data();
    const customFields = currentData.customFields || {};
    
    // Add custom fields for fees
    customFields.fees = [
      {
        key: 'feeType',
        label: 'Fee Type',
        type: 'enum',
        options: ['Tuition', 'Library', 'Transport', 'Exam', 'Hostel', 'Other'],
        required: false
      },
      {
        key: 'paymentMethod',
        label: 'Payment Method',
        type: 'enum',
        options: ['Cash', 'Online', 'Cheque', 'DD'],
        required: false
      },
      {
        key: 'installmentNo',
        label: 'Installment Number',
        type: 'number',
        required: false
      },
      {
        key: 'remarks',
        label: 'Remarks',
        type: 'string',
        required: false,
        maxLength: 200
      }
    ];
    
    await orgRef.update({
      customFields: customFields
    });
    
    console.log('✅ Added custom fields for fees successfully!');
    console.log('Custom fields added:');
    customFields.fees.forEach(field => {
      console.log(`  - ${field.label} (${field.type})`);
    });
    
  } catch (error) {
    console.error('Error:', error);
  } finally {
    process.exit(0);
  }
}

addFeesCustomFields();
